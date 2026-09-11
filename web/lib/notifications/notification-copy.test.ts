import assert from "node:assert/strict";
import { test } from "node:test";
import { isApnsConfigured, readApnsEnvironment } from "@/lib/apns/apns-config";
import { notificationAlert } from "@/lib/notifications/notification-copy";

test("APNs is not configured without server secrets", () => {
  delete process.env.APNS_KEY_ID;
  delete process.env.APNS_PRIVATE_KEY;
  delete process.env.APNS_TOKEN_ENCRYPTION_KEY;
  assert.equal(isApnsConfigured(), false);
  assert.equal(readApnsEnvironment(), null);
});

test("notification copy stays generic on the lock screen", () => {
  const alert = notificationAlert("grace_6h", "en");
  assert.equal(alert.title, "FitFight");
  assert.match(alert.body, /6 hours left/i);
  assert.doesNotMatch(alert.body, /\$/);
});
