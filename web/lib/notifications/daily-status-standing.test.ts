import assert from "node:assert/strict";
import test from "node:test";
import { dailyStatusStanding } from "./daily-status-standing";

test("dailyStatusStanding marks a solo leader", () => {
  assert.equal(
    dailyStatusStanding("a", [{ userId: "a", rank: 1 }]),
    "leading",
  );
});

test("dailyStatusStanding marks tied leaders", () => {
  assert.equal(
    dailyStatusStanding("a", [
      { userId: "a", rank: 1 },
      { userId: "b", rank: 1 },
      { userId: "c", rank: 3 },
    ]),
    "tied_for_lead",
  );
});

test("dailyStatusStanding marks last place", () => {
  assert.equal(
    dailyStatusStanding("c", [
      { userId: "a", rank: 1 },
      { userId: "b", rank: 2 },
      { userId: "c", rank: 3 },
    ]),
    "last",
  );
});
