import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { readApnsEnvironment } from "./apns-config";

export type EncryptedApnsDeviceToken = {
  encryptedToken: string;
  encryptionIv: string;
  encryptionTag: string;
};

export function fingerprintApnsDeviceToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function encryptApnsDeviceToken(token: string): EncryptedApnsDeviceToken {
  const environment = readApnsEnvironment();
  if (!environment) {
    throw new Error("APNS_TOKEN_ENCRYPTION_KEY is not configured");
  }
  const encryptionIv = randomBytes(12);
  const cipher = createCipheriv(
    "aes-256-gcm",
    Buffer.from(environment.tokenEncryptionKey, "base64"),
    encryptionIv,
  );
  const encrypted = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return {
    encryptedToken: encrypted.toString("base64"),
    encryptionIv: encryptionIv.toString("base64"),
    encryptionTag: cipher.getAuthTag().toString("base64"),
  };
}

export function decryptApnsDeviceToken(token: EncryptedApnsDeviceToken): string {
  const environment = readApnsEnvironment();
  if (!environment) {
    throw new Error("APNS_TOKEN_ENCRYPTION_KEY is not configured");
  }
  const decipher = createDecipheriv(
    "aes-256-gcm",
    Buffer.from(environment.tokenEncryptionKey, "base64"),
    Buffer.from(token.encryptionIv, "base64"),
  );
  decipher.setAuthTag(Buffer.from(token.encryptionTag, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(token.encryptedToken, "base64")),
    decipher.final(),
  ]).toString("utf8");
}
