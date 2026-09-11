import { createPrivateKey, sign } from "node:crypto";
import type { ApnsEnvironmentConfig } from "./apns-config";

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
