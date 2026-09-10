import assert from "node:assert/strict";
import { test } from "node:test";
import { isFitFightAdmin } from "./is-fitfight-admin";

function restoreEnv(name: string, previous: string | undefined) {
  if (previous === undefined) delete process.env[name];
  else process.env[name] = previous;
}

test("recognizes the admin username and email", () => {
  assert.equal(isFitFightAdmin({ handle: "marc", emails: [] }), true);
  assert.equal(isFitFightAdmin({ handle: "MARC", emails: [] }), true);
  assert.equal(isFitFightAdmin({
    handle: "maya_moves",
    emails: ["marc@marclamy.com"],
  }), true);
  assert.equal(isFitFightAdmin({
    handle: "maya_moves",
    emails: ["Marc@MarcLamy.com"],
  }), true);
  assert.equal(isFitFightAdmin({
    handle: "maya_moves",
    emails: ["maya@example.com"],
  }), false);
});

test("accepts extra admin emails and handles from env", () => {
  const previousEmails = process.env.FITFIGHT_ADMIN_EMAILS;
  const previousHandles = process.env.FITFIGHT_ADMIN_HANDLES;
  process.env.FITFIGHT_ADMIN_EMAILS = "relay@privaterelay.appleid.com";
  process.env.FITFIGHT_ADMIN_HANDLES = "fitfight_marc";
  try {
    assert.equal(isFitFightAdmin({
      handle: "maya_moves",
      emails: ["relay@privaterelay.appleid.com"],
    }), true);
    assert.equal(isFitFightAdmin({ handle: "fitfight_marc", emails: [] }), true);
  } finally {
    restoreEnv("FITFIGHT_ADMIN_EMAILS", previousEmails);
    restoreEnv("FITFIGHT_ADMIN_HANDLES", previousHandles);
  }
});
