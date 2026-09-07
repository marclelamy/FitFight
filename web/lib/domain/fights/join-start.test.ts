import assert from "node:assert/strict";
import { test } from "node:test";
import { canDeferFightJoin, fightJoinMemberState } from "./join-start";

const startsAt = "2026-09-01T16:00:00.000Z";
const sameDayLater = new Date("2026-09-01T22:00:00.000Z");
const nextDay = new Date("2026-09-02T00:00:01.000Z");
const beforeStart = new Date("2026-09-01T15:59:59.000Z");

test("join next is only after the fight start day", () => {
  assert.equal(
    canDeferFightJoin({
      recurring: true, paused: false, startsAt, timeZone: "UTC", now: sameDayLater,
    }),
    false,
  );
  assert.equal(
    canDeferFightJoin({
      recurring: true, paused: false, startsAt, timeZone: "UTC", now: nextDay,
    }),
    true,
  );
  assert.equal(
    canDeferFightJoin({
      recurring: true, paused: false, startsAt, timeZone: "UTC", now: beforeStart,
    }),
    false,
  );
  assert.equal(
    canDeferFightJoin({
      recurring: false, paused: false, startsAt, timeZone: "UTC", now: nextDay,
    }),
    false,
  );
  assert.equal(
    canDeferFightJoin({
      recurring: true, paused: true, startsAt, timeZone: "UTC", now: nextDay,
    }),
    false,
  );
});

test("the start day follows the fight time zone, not UTC midnight", () => {
  const startEveningUtc = "2026-09-02T02:00:00.000Z";
  const stillStartDayInNewYork = new Date("2026-09-02T03:30:00.000Z");
  const nextDayInNewYork = new Date("2026-09-02T04:00:00.000Z");
  assert.equal(
    canDeferFightJoin({
      recurring: true,
      paused: false,
      startsAt: startEveningUtc,
      timeZone: "America/New_York",
      now: stillStartDayInNewYork,
    }),
    false,
  );
  assert.equal(
    canDeferFightJoin({
      recurring: true,
      paused: false,
      startsAt: startEveningUtc,
      timeZone: "America/New_York",
      now: nextDayInNewYork,
    }),
    true,
  );
});

test("join next becomes deferred only when a next round exists", () => {
  assert.equal(fightJoinMemberState("now", false), "accepted");
  assert.equal(fightJoinMemberState("now", true), "accepted");
  assert.equal(fightJoinMemberState("next", true), "deferred");
  assert.equal(fightJoinMemberState("next", false), null);
});
