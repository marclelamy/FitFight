import { createPrivateKey, sign } from "node:crypto";
import type { ApnsEnvironmentConfig } from "./apns-config";

let cachedProviderToken: {
  keyId: string;
  token: string;
  expiresAtMs: number;
} | null = null;

export function createApnsProviderToken(environment: ApnsEnvironmentConfig, nowMs = Date.now()): string {
  const now = Math.floor(nowMs / 1000);
  const header = Buffer.from(JSON.stringify({
    alg: "ES256",
    kid: environment.keyId,
  })).toString("base64url");
  const claims = Buffer.from(JSON.stringify({
    iss: environment.teamId,
    iat: now,
  })).toString("base64url");
  const unsigned = `${header}.${claims}`;
  const signature = sign("sha256", Buffer.from(unsigned), {
    dsaEncoding: "ieee-p1363",
    key: createPrivateKey(environment.privateKey),
  }).toString("base64url");
  return `${unsigned}.${signature}`;
}

/** Reuse one provider JWT per process; Apple rejects rapid re-mints with TooManyProviderTokenUpdates. */
export function getApnsProviderToken(environment: ApnsEnvironmentConfig, nowMs = Date.now()): string {
  if (
    cachedProviderToken
    && cachedProviderToken.keyId === environment.keyId
    && nowMs < cachedProviderToken.expiresAtMs
  ) {
    return cachedProviderToken.token;
  }
  const token = createApnsProviderToken(environment, nowMs);
  cachedProviderToken = {
    keyId: environment.keyId,
    token,
    expiresAtMs: nowMs + 50 * 60_000,
  };
  return token;
}

export function resetApnsProviderTokenCacheForTests(): void {
  cachedProviderToken = null;
}
