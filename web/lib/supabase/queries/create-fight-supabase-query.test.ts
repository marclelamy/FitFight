import assert from "node:assert/strict";
import { test } from "node:test";
import { createFightSchema, storedFightIdentity } from "./create-fight-supabase-query";

const base = {
  name: "Steps Fight",
  startsAt: "2026-09-04T12:00:00.000Z",
  endsAt: "2026-09-11T12:00:00.000Z",
  timeZone: "Europe/Paris",
  outcomeRule: "highest_total" as const,
  stakeKind: "action" as const,
  actionText: "Cook dinner",
};

test("private create can start with the owner alone", () => {
  const parsed = createFightSchema.parse({
    ...base,
    visibility: "invite_only",
    inviteHandles: [],
  });
  assert.equal(parsed.visibility, "invite_only");
  assert.deepEqual(parsed.inviteHandles, []);
});

test("joinable create can start with the owner alone", () => {
  const parsed = createFightSchema.parse({
    ...base,
    visibility: "joinable",
    recurring: true,
  });
  assert.equal(parsed.visibility, "joinable");
  assert.equal(parsed.recurring, true);
  assert.deepEqual(parsed.inviteHandles, undefined);
});

test("visibility defaults to invite-only and recurring is on", () => {
  const parsed = createFightSchema.parse({
    ...base,
    inviteHandles: ["leo_runs"],
  });
  assert.equal(parsed.visibility, "invite_only");
  assert.equal(parsed.recurring, true);
});

test("create can turn recurring off", () => {
  const parsed = createFightSchema.parse({
    ...base,
    visibility: "joinable",
    recurring: false,
  });
  assert.equal(parsed.recurring, false);
});

test("create allows an optional title and action", () => {
  assert.equal(
    createFightSchema.safeParse({ ...base, visibility: "joinable", actionText: undefined }).success,
    true,
  );
  assert.equal(
    createFightSchema.safeParse({ ...base, visibility: "joinable", actionText: "   ", name: "" }).success,
    true,
  );
  assert.deepEqual(storedFightIdentity("Office steps", "Cook dinner"), {
    name: "Office steps",
    actionText: "Cook dinner",
  });
  assert.deepEqual(storedFightIdentity("", "Cook dinner"), {
    name: "Cook dinner",
    actionText: "Cook dinner",
  });
  assert.deepEqual(storedFightIdentity("Office steps", "  "), {
    name: "Office steps",
    actionText: null,
  });
  assert.deepEqual(storedFightIdentity("  ", undefined), {
    name: "Steps Fight",
    actionText: null,
  });
});
