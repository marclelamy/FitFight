import assert from "node:assert/strict";
import { test } from "node:test";
import { addCalendarDay, civilDayBounds, civilDayStamp, isCivilDay, resolveTimeZone } from "./civil-day";

test("civil day bounds use the profile time zone", () => {
  const utc = civilDayBounds("2026-08-24", "UTC");
  assert.equal(utc.externalRecordId, "day:2026-08-24");
  assert.equal(utc.startsAt.toISOString(), "2026-08-24T00:00:00.000Z");
  assert.equal(utc.endsAt.toISOString(), "2026-08-25T00:00:00.000Z");

  const edt = civilDayBounds("2026-08-24", "America/New_York");
  assert.equal(edt.startsAt.toISOString(), "2026-08-24T04:00:00.000Z");
  assert.equal(edt.endsAt.toISOString(), "2026-08-25T04:00:00.000Z");

  const est = civilDayBounds("2026-01-15", "America/New_York");
  assert.equal(est.startsAt.toISOString(), "2026-01-15T05:00:00.000Z");
  assert.equal(est.endsAt.toISOString(), "2026-01-16T05:00:00.000Z");
});

test("invalid days and time zones are rejected or fall back", () => {
  assert.equal(isCivilDay("2026-13-40"), false);
  assert.equal(isCivilDay("08-24-2026"), false);
  assert.equal(addCalendarDay("2026-08-31"), "2026-09-01");
  assert.equal(resolveTimeZone("Not/AZone"), "UTC");
  assert.equal(resolveTimeZone(null), "UTC");
});

test("civil day stamps follow the fight time zone", () => {
  assert.equal(civilDayStamp(new Date("2026-09-02T03:30:00.000Z"), "America/New_York"), "2026-09-01");
  assert.equal(civilDayStamp(new Date("2026-09-02T04:00:00.000Z"), "America/New_York"), "2026-09-02");
  assert.equal(civilDayStamp(new Date("2026-09-02T00:00:00.000Z"), "UTC"), "2026-09-02");
});
