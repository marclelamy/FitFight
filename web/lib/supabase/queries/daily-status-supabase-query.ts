import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { dailyStatusStanding } from "@/lib/notifications/daily-status-standing";
import { generateDailyStatusCopy, isOpenRouterConfigured } from "@/lib/openrouter/generate-daily-status";
import {
  dailyStatusRecapResponseSchema,
  type DailyStatusPromptContext,
} from "@/lib/types/notifications/daily-status";

const DAY_MS = 86_400_000;
const BATCH = 40;

type LiveMemberRow = {
  fight_id: string;
  user_id: string;
  rank: number | null;
  last_synced_at: string | null;
  ends_at: string;
  starts_at: string;
  participant_count: number;
  locale: string | null;
};

export type EnqueueDailyStatusNotificationsResult = {
  configured: boolean;
  candidates: number;
  enqueued: number;
  skipped: number;
  failed: number;
};

function utcDayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function idempotencyKey(fightId: string, userId: string, dayKey: string): string {
  return `${fightId}:${userId}:daily_status:daily:${dayKey}`;
}

function routeForFight(fightId: string): string {
  return `/fights/${fightId}?daily_status=1`;
}

function localeForRow(locale: string | null): DailyStatusPromptContext["locale"] {
  return locale === "fr" ? "fr" : "en";
}

function daysRemaining(endsAt: string, now: Date): number {
  const remainingMs = Date.parse(endsAt) - now.getTime();
  if (remainingMs <= 0) {
    return 0;
  }
  return Math.max(1, Math.ceil(remainingMs / DAY_MS));
}

function needsSync(lastSyncedAt: string | null, now: Date): boolean {
  if (!lastSyncedAt) {
    return true;
  }
  return now.getTime() - Date.parse(lastSyncedAt) > DAY_MS;
}

async function readLiveMemberRows(database: Sql): Promise<LiveMemberRow[]> {
  return database<LiveMemberRow[]>`
    select fight.id as fight_id,
      member.user_id,
      member.rank,
      member.last_synced_at,
      fight.ends_at,
      fight.starts_at,
      counts.participant_count,
      installation.locale
    from public.fights as fight
    join public.fight_members as member
      on member.fight_id = fight.id
      and member.state = 'accepted'
    join lateral (
      select count(*)::int as participant_count
      from public.fight_members as accepted
      where accepted.fight_id = fight.id
        and accepted.state = 'accepted'
    ) as counts on true
    left join lateral (
      select locale
      from private.device_installations as device
      where device.user_id = member.user_id
        and device.revoked_at is null
      order by device.last_registered_at desc
      limit 1
    ) as installation on true
    where fight.state = 'live'
    order by fight.id, member.user_id
  `;
}

async function readFightMembers(
  database: Sql,
  fightId: string,
): Promise<Array<{ user_id: string; rank: number | null }>> {
  return database<{ user_id: string; rank: number | null }[]>`
    select user_id, rank
    from public.fight_members
    where fight_id = ${fightId}
      and state = 'accepted'
  `;
}

async function insertDailyStatusIntent(
  database: Sql,
  row: LiveMemberRow,
  dayKey: string,
  notBefore: string,
  expiresAt: string,
  alertBody: string,
  recapBody: string,
): Promise<boolean> {
  const inserted = await database<{ id: string }[]>`
    insert into private.notification_intents (
      idempotency_key, user_id, fight_id, kind, slot,
      not_before, expires_at, route, copy_key, alert_body, recap_body
    ) values (
      ${idempotencyKey(row.fight_id, row.user_id, dayKey)},
      ${row.user_id},
      ${row.fight_id},
      'daily_status',
      'daily',
      ${notBefore}::timestamptz,
      ${expiresAt}::timestamptz,
      ${routeForFight(row.fight_id)},
      'daily_status',
      ${alertBody},
      ${recapBody}
    )
    on conflict (idempotency_key) do nothing
    returning id
  `;
  return inserted.length > 0;
}

export async function enqueueDailyStatusNotifications(
  now: Date = new Date(),
  database: Sql = createDatabaseClient(),
): Promise<EnqueueDailyStatusNotificationsResult> {
  const result: EnqueueDailyStatusNotificationsResult = {
    configured: isOpenRouterConfigured(),
    candidates: 0,
    enqueued: 0,
    skipped: 0,
    failed: 0,
  };
  if (!result.configured) {
    return result;
  }

  const rows = await readLiveMemberRows(database);
  result.candidates = rows.length;
  if (rows.length === 0) {
    return result;
  }

  const dayKey = utcDayKey(now);
  const notBefore = now.toISOString();
  const expiresAt = new Date(now.getTime() + 20 * 3_600_000).toISOString();
  const membersByFight = new Map<string, Array<{ user_id: string; rank: number | null }>>();

  for (const row of rows) {
    if (!membersByFight.has(row.fight_id)) {
      membersByFight.set(row.fight_id, await readFightMembers(database, row.fight_id));
    }
    const members = membersByFight.get(row.fight_id) ?? [];
    const context: DailyStatusPromptContext = {
      standing: dailyStatusStanding(row.user_id, members.map((member) => ({
        userId: member.user_id,
        rank: member.rank,
      }))),
      participant_count: row.participant_count,
      days_remaining: daysRemaining(row.ends_at, now),
      needs_sync: needsSync(row.last_synced_at, now),
      locale: localeForRow(row.locale),
    };

    try {
      const copy = await generateDailyStatusCopy(context);
      const inserted = await insertDailyStatusIntent(
        database,
        row,
        dayKey,
        notBefore,
        expiresAt,
        copy.alert,
        copy.recap,
      );
      if (inserted) {
        result.enqueued += 1;
      } else {
        result.skipped += 1;
      }
    } catch {
      result.failed += 1;
    }
  }

  return result;
}

export async function readDailyStatusRecap(
  userId: string,
  fightId: string,
  database: Sql = createDatabaseClient(),
): Promise<{ recap: string; sent_at: string } | null> {
  const [member] = await database<{ user_id: string }[]>`
    select user_id
    from public.fight_members
    where fight_id = ${fightId}
      and user_id = ${userId}
      and state = 'accepted'
    limit 1
  `;
  if (!member) {
    return null;
  }

  const [row] = await database<{ recap_body: string; created_at: Date | string }[]>`
    select recap_body, created_at
    from private.notification_intents
    where user_id = ${userId}
      and fight_id = ${fightId}
      and kind = 'daily_status'
      and recap_body is not null
    order by created_at desc
    limit 1
  `;
  if (!row) {
    return null;
  }

  return dailyStatusRecapResponseSchema.parse({
    recap: row.recap_body,
    sent_at: new Date(row.created_at).toISOString(),
  });
}
