import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import { iosInstall } from "./ios-install";

const originalStoreURL = process.env.NEXT_PUBLIC_IOS_APP_STORE_URL;
const originalStoreId = process.env.NEXT_PUBLIC_IOS_APP_STORE_ID;

afterEach(() => {
  if (originalStoreURL === undefined) {
    delete process.env.NEXT_PUBLIC_IOS_APP_STORE_URL;
  } else {
    process.env.NEXT_PUBLIC_IOS_APP_STORE_URL = originalStoreURL;
  }
  if (originalStoreId === undefined) {
    delete process.env.NEXT_PUBLIC_IOS_APP_STORE_ID;
  } else {
    process.env.NEXT_PUBLIC_IOS_APP_STORE_ID = originalStoreId;
  }
});

test("staging and previews stay on TestFlight", () => {
  process.env.NEXT_PUBLIC_IOS_APP_STORE_URL = "https://apps.apple.com/app/id000";
  process.env.NEXT_PUBLIC_IOS_APP_STORE_ID = "000";
  const staging = iosInstall("staging.fitfight.app");
  assert.equal(staging.channel, "testflight");
  assert.match(staging.url, /testflight\.apple\.com/);
  assert.equal(iosInstall("localhost:3000").channel, "testflight");
  assert.equal(iosInstall("fit-fight-git-abc.vercel.app").channel, "testflight");
});

test("production uses the App Store only when a store URL is set", () => {
  delete process.env.NEXT_PUBLIC_IOS_APP_STORE_URL;
  delete process.env.NEXT_PUBLIC_IOS_APP_STORE_ID;
  assert.equal(iosInstall("fitfight.app").channel, "testflight");

  process.env.NEXT_PUBLIC_IOS_APP_STORE_URL = "https://apps.apple.com/app/id1234567890";
  process.env.NEXT_PUBLIC_IOS_APP_STORE_ID = "1234567890";
  const production = iosInstall("www.fitfight.app");
  assert.equal(production.channel, "appStore");
  assert.equal(production.url, "https://apps.apple.com/app/id1234567890");
  assert.equal(production.appStoreId, "1234567890");
});
