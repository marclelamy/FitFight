import assert from "node:assert/strict";
import { test } from "node:test";
import { competitionRank, fightPot, scoreFight, scoreFightAtFinal } from "./score-fight";

test("fight pot is stake times accepted count", () => {
  assert.equal(fightPot(1000, 3), 3000);
  assert.equal(fightPot(null, 3), 0);
  assert.equal(fightPot(500, 0), 0);
});

test("highest total ranks members and splits ties deterministically", () => {
  const winner = scoreFight({
    outcomeRule: "highest_total",
    stakeMinor: 1000,
    defaultGoalValue: null,
    members: [
      { userId: "b", value: 8000, personalTarget: null },
      { userId: "a", value: 12000, personalTarget: null },
      { userId: "c", value: 8000, personalTarget: null },
    ],
  });
  assert.deepEqual(
    winner.map(({ userId, rank, outcomeMinor }) => ({ userId, rank, outcomeMinor })),
    [
      { userId: "a", rank: 1, outcomeMinor: 3000 },
      { userId: "b", rank: 2, outcomeMinor: 0 },
      { userId: "c", rank: 2, outcomeMinor: 0 },
    ],
  );

  const tie = scoreFight({
    outcomeRule: "highest_total",
    stakeMinor: 333,
    defaultGoalValue: null,
    members: [
      { userId: "c", value: 10, personalTarget: null },
      { userId: "a", value: 10, personalTarget: null },
      { userId: "b", value: 10, personalTarget: null },
    ],
  });
  assert.equal(tie.reduce((sum, row) => sum + row.outcomeMinor, 0), 999);
  assert.equal(competitionRank(10, [10, 10, 10]), 1);
});

test("proportional and goal scoring allocate the complete pot", () => {
  const proportional = scoreFight({
    outcomeRule: "proportional",
    stakeMinor: 100,
    defaultGoalValue: null,
    members: [
      { userId: "a", value: 2, personalTarget: null },
      { userId: "b", value: 1, personalTarget: null },
    ],
  });
  assert.equal(proportional.find((row) => row.userId === "a")?.outcomeMinor, 133);
  assert.equal(proportional.find((row) => row.userId === "b")?.outcomeMinor, 67);

  const goals = scoreFight({
    outcomeRule: "hit_your_goal",
    stakeMinor: 1000,
    defaultGoalValue: 8000,
    members: [
      { userId: "a", value: 9000, personalTarget: 8000 },
      { userId: "b", value: 5000, personalTarget: null },
    ],
  });
  assert.equal(goals.find((row) => row.userId === "a")?.outcomeMinor, 2000);
  assert.equal(goals.find((row) => row.userId === "a")?.hitGoal, true);
  assert.equal(goals.find((row) => row.userId === "b")?.outcomeMinor, 0);
});

test("final forfeit: a high incomplete total loses to a low complete total", () => {
  const rows = scoreFightAtFinal({
    outcomeRule: "highest_total",
    stakeMinor: 1000,
    defaultGoalValue: null,
    members: [
      { userId: "partial", value: 81500, personalTarget: null, complete: false },
      { userId: "submitted", value: 100, personalTarget: null, complete: true },
    ],
  });
  assert.deepEqual(
    rows.map(({ userId, currentValue, rank, outcomeMinor }) => ({
      userId, currentValue, rank, outcomeMinor,
    })),
    [
      { userId: "submitted", currentValue: 100, rank: 1, outcomeMinor: 1000 },
      { userId: "partial", currentValue: 81500, rank: 2, outcomeMinor: 0 },
    ],
  );
});

test("final forfeit: both incomplete is a draw at rank 1 and keeps last values", () => {
  const rows = scoreFightAtFinal({
    outcomeRule: "highest_total",
    stakeMinor: 1000,
    defaultGoalValue: null,
    members: [
      { userId: "a", value: 42, personalTarget: null, complete: false },
      { userId: "b", value: 0, personalTarget: null, complete: false },
    ],
  });
  assert.deepEqual(
    rows.map(({ userId, currentValue, rank, outcomeMinor }) => ({
      userId, currentValue, rank, outcomeMinor,
    })),
    [
      { userId: "a", currentValue: 42, rank: 1, outcomeMinor: 0 },
      { userId: "b", currentValue: 0, rank: 1, outcomeMinor: 0 },
    ],
  );
});

test("final forfeit: three people use two-tier rank regardless of input order", () => {
  const rows = scoreFightAtFinal({
    outcomeRule: "highest_total",
    stakeMinor: null,
    defaultGoalValue: null,
    members: [
      { userId: "a", value: 9000, personalTarget: null, complete: false },
      { userId: "b", value: 100, personalTarget: null, complete: true },
      { userId: "c", value: 500, personalTarget: null, complete: true },
    ],
  });
  assert.deepEqual(
    rows.map(({ userId, currentValue, rank }) => ({ userId, currentValue, rank })),
    [
      { userId: "c", currentValue: 500, rank: 1 },
      { userId: "b", currentValue: 100, rank: 2 },
      { userId: "a", currentValue: 9000, rank: 3 },
    ],
  );
});

test("final scoring matches live scoring when every accepted member is complete", () => {
  const members = [
    { userId: "a", value: 12000, personalTarget: null },
    { userId: "b", value: 8000, personalTarget: null },
    { userId: "c", value: 8000, personalTarget: null },
  ];
  const args = {
    outcomeRule: "highest_total" as const,
    stakeMinor: 1000,
    defaultGoalValue: null,
  };
  assert.deepEqual(
    scoreFightAtFinal({ ...args, members: members.map((member) => ({ ...member, complete: true })) }),
    scoreFight({ ...args, members }),
  );
});
