import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import {
  decryptApnsDeviceToken,
  encryptApnsDeviceToken,
  fingerprintApnsDeviceToken,
} from "@/lib/apns/apns-token-crypto";
import { isApnsConfigured } from "@/lib/apns/apns-config";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { RegisterDeviceInstallationRequest } from "@/lib/types/notifications/device-installation";

export async function registerDeviceInstallation(
  userId: string,
  input: RegisterDeviceInstallationRequest,
  database: Sql = createDatabaseClient(),
): Promise<{ registered: true }> {
  if (!isApnsConfigured()) {
    throw new ApiError(503, ERROR_CODES.config, "Push notifications are not configured yet");
  }
  const encrypted = encryptApnsDeviceToken(input.token);
  const fingerprint = fingerprintApnsDeviceToken(input.token);
  await database`
    insert into private.device_installations (
      user_id,
      token_fingerprint,
      encrypted_token,
      encryption_iv,
      encryption_tag,
      apns_environment,
      locale,
      permission_status,
      last_registered_at,
      revoked_at,
      revoke_reason
    ) values (
      ${userId},
      ${fingerprint},
      ${encrypted.encryptedToken},
      ${encrypted.encryptionIv},
      ${encrypted.encryptionTag},
      ${input.apns_environment},
      ${input.locale},
      ${input.permission_status},
      now(),
      null,
      null
    )
    on conflict (token_fingerprint) do update set
      user_id = excluded.user_id,
      encrypted_token = excluded.encrypted_token,
      encryption_iv = excluded.encryption_iv,
      encryption_tag = excluded.encryption_tag,
      apns_environment = excluded.apns_environment,
      locale = excluded.locale,
      permission_status = excluded.permission_status,
      last_registered_at = now(),
      revoked_at = null,
      revoke_reason = null
  `;
  return { registered: true };
}

export async function revokeDeviceInstallationsForUser(
  userId: string,
  reason: string,
  database: Sql,
): Promise<void> {
  await database`
    update private.device_installations
    set revoked_at = now(),
      revoke_reason = ${reason}
    where user_id = ${userId}
      and revoked_at is null
  `;
}

export type ActiveDeviceInstallation = {
  id: string;
  encrypted_token: string;
  encryption_iv: string;
  encryption_tag: string;
  apns_environment: "sandbox" | "production";
  locale: "en" | "fr" | null;
};

export async function readActiveDeviceInstallations(
  userId: string,
  database: Sql,
): Promise<ActiveDeviceInstallation[]> {
  return database<ActiveDeviceInstallation[]>`
    select id, encrypted_token, encryption_iv, encryption_tag, apns_environment, locale
    from private.device_installations
    where user_id = ${userId}
      and revoked_at is null
    order by last_registered_at desc
  `;
}

export function decryptInstallationToken(installation: ActiveDeviceInstallation): string {
  return decryptApnsDeviceToken({
    encryptedToken: installation.encrypted_token,
    encryptionIv: installation.encryption_iv,
    encryptionTag: installation.encryption_tag,
  });
}

export async function revokeDeviceInstallation(
  installationId: string,
  reason: string,
  database: Sql,
): Promise<void> {
  await database`
    update private.device_installations
    set revoked_at = now(),
      revoke_reason = ${reason}
    where id = ${installationId}
      and revoked_at is null
  `;
}
