import { z } from "zod";

const apnsEnvironmentSchema = z.object({
  keyId: z.string().regex(/^[A-Z0-9]{10}$/),
  teamId: z.string().regex(/^[A-Z0-9]{10}$/),
  privateKey: z.string().includes("BEGIN PRIVATE KEY"),
  topic: z.string().min(1).max(255),
  tokenEncryptionKey: z.string().base64().refine(
    (value) => Buffer.from(value, "base64").byteLength === 32,
    "must be a base64-encoded 32-byte key",
  ),
});

export type ApnsEnvironmentConfig = z.infer<typeof apnsEnvironmentSchema>;

export function readApnsEnvironment(): ApnsEnvironmentConfig | null {
  const parsed = apnsEnvironmentSchema.safeParse({
    keyId: process.env.APNS_KEY_ID,
    teamId: process.env.APNS_TEAM_ID ?? process.env.APPLE_TEAM_ID,
    privateKey: process.env.APNS_PRIVATE_KEY?.replace(/\\n/g, "\n"),
    topic: process.env.APNS_TOPIC ?? "com.fitfight.mvp",
    tokenEncryptionKey: process.env.APNS_TOKEN_ENCRYPTION_KEY,
  });
  return parsed.success ? parsed.data : null;
}

export function isApnsConfigured(): boolean {
  return readApnsEnvironment() !== null;
}
