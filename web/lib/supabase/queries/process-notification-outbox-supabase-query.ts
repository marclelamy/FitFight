import type { Sql } from "postgres";
import { sendApnsAlert } from "@/lib/apns/apns-client";
import { isApnsConfigured, readApnsEnvironment } from "@/lib/apns/apns-config";
import { notificationAlert } from "@/lib/notifications/notification-copy";
import { pendingNotificationIntentSchema } from "@/lib/types/notifications/notification-intent";
import {
  decryptInstallationToken,
  readActiveDeviceInstallations,
  revokeDeviceInstallation,
} from "./device-installations-supabase-query";

const BATCH = 50;

export type ProcessNotificationOutboxResult = {
  checked: number;
  sent: number;
  skipped: number;
  failed: number;
  expired: number;
  pending: number;
};

type IntentRow = {
  id: string;
  user_id: string;
  fight_id: string;
  kind: string;
  slot: string;
  route: string;
  copy_key: string;
  fight_state: string | null;
  final_steps_complete: boolean | null;
};

async function markIntent(
  sql: Sql,
  intentId: string,
  status: "skipped" | "sent" | "failed" | "expired",
  skipReason?: string,
): Promise<void> {
  await sql`
    update private.notification_intents
    set status = ${status},
      skip_reason = ${skipReason ?? null},
      processed_at = now()
    where id = ${intentId}
  `;
}

async function recordDelivery(
  sql: Sql,
  intentId: string,
  installationId: string,
  attempt: number,
  httpStatus: number | null,
  reason: string | null,
): Promise<void> {
  await sql`
    insert into private.notification_deliveries (
      intent_id, installation_id, attempt, apns_http_status, apns_reason
    ) values (
      ${intentId}, ${installationId}, ${attempt}, ${httpStatus}, ${reason}
    )
  `;
}

export async function processNotificationOutbox(
  now: Date = new Date(),
  database: Sql,
): Promise<ProcessNotificationOutboxResult> {
  const result: ProcessNotificationOutboxResult = {
    checked: 0,
    sent: 0,
    skipped: 0,
    failed: 0,
    expired: 0,
    pending: 0,
  };
  const nowIso = now.toISOString();

  await database`
    update private.notification_intents
    set status = 'expired',
      processed_at = now()
    where status = 'pending'
      and expires_at <= ${nowIso}::timestamptz
  `;

  const rows = await database<IntentRow[]>`
    select intent.id, intent.user_id, intent.fight_id, intent.kind, intent.slot,
      intent.route, intent.copy_key, fight.state::text as fight_state,
      member.final_steps_complete
    from private.notification_intents as intent
    left join public.fights as fight on fight.id = intent.fight_id
    left join public.fight_members as member
      on member.fight_id = intent.fight_id
      and member.user_id = intent.user_id
      and member.state = 'accepted'
    where intent.status = 'pending'
      and intent.not_before <= ${nowIso}::timestamptz
      and intent.expires_at > ${nowIso}::timestamptz
    order by intent.not_before, intent.id
    limit ${BATCH}
  `;

  result.checked = rows.length;
  if (rows.length === 0) {
    return result;
  }

  const apnsConfigured = isApnsConfigured();
  const apnsEnvironment = readApnsEnvironment();

  for (const row of rows) {
    const intent = pendingNotificationIntentSchema.parse({
      id: row.id,
      user_id: row.user_id,
      fight_id: row.fight_id,
      kind: row.kind,
      slot: row.slot,
      route: row.route,
      copy_key: row.copy_key,
    });

    if (row.fight_state === "cancelled" || row.fight_state === null) {
      await markIntent(database, intent.id, "skipped", "fight_cancelled");
      result.skipped += 1;
      continue;
    }

    if (
      intent.kind === "grace_reminder"
      && row.final_steps_complete === true
    ) {
      await markIntent(database, intent.id, "skipped", "already_complete");
      result.skipped += 1;
      continue;
    }

    if (!apnsConfigured || !apnsEnvironment) {
      result.pending += 1;
      continue;
    }

    const installations = await readActiveDeviceInstallations(intent.user_id, database);
    if (installations.length === 0) {
      await markIntent(database, intent.id, "skipped", "no_token");
      result.skipped += 1;
      continue;
    }

    const alert = notificationAlert(intent.copy_key, installations[0]?.locale);
    let delivered = false;
    let retryLater = false;
    let invalidProviderToken = false;

    for (const [index, installation] of installations.entries()) {
      const attempt = index + 1;
      let deviceToken: string;
      try {
        deviceToken = decryptInstallationToken(installation);
      } catch {
        await revokeDeviceInstallation(installation.id, "decrypt_failed", database);
        continue;
      }

      const sendResult = await sendApnsAlert({
        deviceToken,
        environment: installation.apns_environment,
        topic: apnsEnvironment.topic,
        title: alert.title,
        body: alert.body,
        route: intent.route,
      });

      await recordDelivery(
        database,
        intent.id,
        installation.id,
        attempt,
        sendResult.httpStatus,
        sendResult.reason,
      );

      if (sendResult.invalidProviderToken) {
        invalidProviderToken = true;
        break;
      }
      if (sendResult.retryLater) {
        retryLater = true;
        break;
      }
      if (sendResult.unregistered) {
        await revokeDeviceInstallation(installation.id, sendResult.reason ?? "unregistered", database);
        continue;
      }
      if (sendResult.httpStatus === 200) {
        delivered = true;
        break;
      }
    }

    if (invalidProviderToken) {
      result.pending += 1;
      continue;
    }
    if (retryLater) {
      result.pending += 1;
      continue;
    }
    if (delivered) {
      await markIntent(database, intent.id, "sent");
      result.sent += 1;
      continue;
    }

    await markIntent(database, intent.id, "skipped", "no_token");
    result.skipped += 1;
  }

  return result;
}
