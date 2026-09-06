import assert from "node:assert/strict";
import { test } from "node:test";
import { canDeferFightJoin, fightJoinMemberState } from "./join-start";

const startsAt = "2026-09-01T12:00:00.000Z";
const midWindow = new Date("2026-09-04T12:00:00.000Z");
const beforeStart = new Date("2026-09-01T11:59:59.000Z");

test("join next is only for a repeating fight that already started", () => {
  assert.equal(
    canDeferFightJoin({ recurring: true, paused: false, startsAt, now: midWindow }),
    true,
  );
  assert.equal(
    canDeferFightJoin({ recurring: true, paused: false, startsAt, now: beforeStart }),
    false,
  );
  assert.equal(
    canDeferFightJoin({ recurring: false, paused: false, startsAt, now: midWindow }),
    false,
  );
  assert.equal(
    canDeferFightJoin({ recurring: true, paused: true, startsAt, now: midWindow }),
    false,
  );
});

test("join next becomes deferred only when a next round exists", () => {
  assert.equal(fightJoinMemberState("now", false), "accepted");
  assert.equal(fightJoinMemberState("now", true), "accepted");
  assert.equal(fightJoinMemberState("next", true), "deferred");
  assert.equal(fightJoinMemberState("next", false), null);
});
