import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes } from "node:crypto";
import { test } from "node:test";
import { getApnsProviderToken, resetApnsProviderTokenCacheForTests } from "./apns-jwt";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const environment = {
  keyId: "ABCDE12345",
  teamId: "TEAM123456",
  privateKey: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
  topic: "com.fitfight.mvp",
  tokenEncryptionKey: randomBytes(32).toString("base64"),
};

test("getApnsProviderToken reuses the same JWT until the cache expires", () => {
  resetApnsProviderTokenCacheForTests();
  const first = getApnsProviderToken(environment, Date.parse("2026-09-11T12:00:00.000Z"));
  const second = getApnsProviderToken(environment, Date.parse("2026-09-11T12:10:00.000Z"));
  const refreshed = getApnsProviderToken(environment, Date.parse("2026-09-11T13:01:00.000Z"));
  assert.equal(second, first);
  assert.notEqual(refreshed, first);
  assert.match(first, /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
});
