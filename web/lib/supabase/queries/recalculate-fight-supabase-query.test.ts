import assert from "node:assert/strict";
import { test } from "node:test";
import postgres, { type Sql } from "postgres";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const json = postgres().json;

test("finalizing a fight uses a bounded number of writes as the roster grows", async () => {
  const statementCounts: number[] = [];
  const fightId = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";
  const endsAt = "2026-09-03T16:06:35.093Z";
  for (const memberCount of [2, 20]) {
    const members = Array.from({ length: memberCount }, (_, index) => ({
      user_id: `a0000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
      personal_target: null,
      input_revision: index,
    }));
    const snapshots = members.map((member, index) => ({
      id: `c0000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
      user_id: member.user_id,
      value: String(100 - index),
      cutoff_at: endsAt,
    }));
    const queries: Array<{ query: string; values: readonly unknown[] }> = [];
    const transaction = Object.assign((strings: TemplateStringsArray, ...values: unknown[]) => {
      const query = strings.join("?");
      queries.push({ query, values });
      if (query.includes("from public.fights")) return Promise.resolve([{
        state: "live", starts_at: "2026-08-27T16:06:36.729Z", ends_at: endsAt,
        final_sync_grace_seconds: 86_400, outcome_rule: "highest_total",
        stake_minor: null, default_goal_value: null,
      }]);
      if (query.includes("from public.fight_members")) return Promise.resolve(members);
      if (query.includes("from private.fight_score_snapshots")) return Promise.resolve(snapshots);
      return Promise.resolve([]);
    }, { array: (values: readonly unknown[]) => values, json });
    const database = Object.assign(() => { throw new Error("query must run inside a transaction"); }, {
      begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) =>
        callback(transaction as unknown as Sql),
    }) as unknown as Sql;

    await recalculateFight(fightId, new Date("2026-09-03T17:00:00.000Z"), database);
    statementCounts.push(queries.length);
    const memberUpdates = queries.filter(({ query }) => query.includes("update public.fight_members"));
    assert.equal(memberUpdates.length, 1);
    assert.ok(memberUpdates[0].values.includes(memberCount), "every member receives the next common revision");
    assert.ok(
      memberUpdates[0].query.includes("and member.finalized_at is null"),
      "live scores stay mutable until the fight finalizes",
    );
    assert.ok(
      !memberUpdates[0].query.includes("final_value"),
      "member freeze waits for fight finalization",
    );
    const memberPayload = memberUpdates[0].values.find((value) =>
      JSON.stringify(value).includes('"final_steps_complete"')
    );
    assert.deepEqual(memberPayload, json(members.map((member, index) => ({
      user_id: member.user_id,
      current_value: 100 - index,
      rank: index + 1,
      outcome_minor: 0,
      final_steps_complete: true,
    }))));
    const snapshotUpdates = queries.filter(({ query }) => query.includes("set is_final"));
    assert.equal(snapshotUpdates.length, 1);
    assert.deepEqual(snapshotUpdates[0].values, [snapshots.map((snapshot) => snapshot.id)]);
    assert.ok(queries.some(({ query, values }) =>
      query.includes("update public.fights set state") && values.includes("final")
    ));
  }

  assert.equal(statementCounts[1], statementCounts[0], "roster size must not add database round trips");
  assert.ok(statementCounts.every((count) => count <= 9), `expected at most 9 statements, got ${statementCounts}`);
});

function mockRecalculateDatabase(input: {
  endsAt: string;
  members: Array<{ user_id: string; personal_target: null; input_revision: number }>;
  snapshots: Array<{ id: string; user_id: string; value: string; cutoff_at: string }>;
}) {
  const queries: Array<{ query: string; values: readonly unknown[] }> = [];
  const transaction = Object.assign((strings: TemplateStringsArray, ...values: unknown[]) => {
    const query = strings.join("?");
    queries.push({ query, values });
    if (query.includes("from public.fights")) return Promise.resolve([{
      state: "live", starts_at: "2026-08-27T16:06:36.729Z", ends_at: input.endsAt,
      final_sync_grace_seconds: 86_400, outcome_rule: "highest_total",
      stake_minor: null, default_goal_value: null,
    }]);
    if (query.includes("from public.fight_members")) return Promise.resolve(input.members);
    if (query.includes("from private.fight_score_snapshots")) return Promise.resolve(input.snapshots);
    return Promise.resolve([]);
  }, { array: (values: readonly unknown[]) => values, json });
  const database = Object.assign(() => { throw new Error("query must run inside a transaction"); }, {
    begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) =>
      callback(transaction as unknown as Sql),
  }) as unknown as Sql;
  return { database, queries };
}

test("awaiting_final_sync still ranks by raw score; final forfeits incomplete members", async () => {
  const fightId = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";
  const endsAt = "2026-09-03T16:06:35.093Z";
  const members = [
    { user_id: "a0000000-0000-4000-8000-000000000000", personal_target: null, input_revision: 0 },
    { user_id: "a0000000-0000-4000-8000-000000000001", personal_target: null, input_revision: 1 },
    { user_id: "a0000000-0000-4000-8000-000000000002", personal_target: null, input_revision: 2 },
  ];
  const snapshots = [
    { id: "c0000000-0000-4000-8000-000000000000", user_id: members[0].user_id, value: "9000", cutoff_at: "2026-09-03T16:00:00.000Z" },
    { id: "c0000000-0000-4000-8000-000000000001", user_id: members[1].user_id, value: "100", cutoff_at: endsAt },
    { id: "c0000000-0000-4000-8000-000000000002", user_id: members[2].user_id, value: "500", cutoff_at: endsAt },
  ];

  const awaiting = mockRecalculateDatabase({ endsAt, members, snapshots });
  await recalculateFight(fightId, new Date("2026-09-03T17:00:00.000Z"), awaiting.database);
  const awaitingPayload = awaiting.queries
    .find(({ query }) => query.includes("update public.fight_members"))
    ?.values.find((value) => JSON.stringify(value).includes('"final_steps_complete"'));
  assert.deepEqual(awaitingPayload, json([
    { user_id: members[0].user_id, current_value: 9000, rank: 1, outcome_minor: 0, final_steps_complete: false },
    { user_id: members[2].user_id, current_value: 500, rank: 2, outcome_minor: 0, final_steps_complete: true },
    { user_id: members[1].user_id, current_value: 100, rank: 3, outcome_minor: 0, final_steps_complete: true },
  ]));
  assert.ok(awaiting.queries.some(({ query, values }) =>
    query.includes("update public.fights set state") && values.includes("awaiting_final_sync")
  ));

  const finalized = mockRecalculateDatabase({ endsAt, members, snapshots });
  await recalculateFight(fightId, new Date("2026-09-05T16:06:35.093Z"), finalized.database);
  const finalPayload = finalized.queries
    .find(({ query }) => query.includes("update public.fight_members"))
    ?.values.find((value) => JSON.stringify(value).includes('"final_steps_complete"'));
  assert.deepEqual(finalPayload, json([
    { user_id: members[2].user_id, current_value: 500, rank: 1, outcome_minor: 0, final_steps_complete: true },
    { user_id: members[1].user_id, current_value: 100, rank: 2, outcome_minor: 0, final_steps_complete: true },
    { user_id: members[0].user_id, current_value: 9000, rank: 3, outcome_minor: 0, final_steps_complete: false },
  ]));
  assert.ok(finalized.queries.some(({ query, values }) =>
    query.includes("update public.fights set state") && values.includes("final")
  ));
});

test("finalizing with every member incomplete is a draw and keeps last verified totals", async () => {
  const fightId = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";
  const endsAt = "2026-09-03T16:06:35.093Z";
  const members = [
    { user_id: "a0000000-0000-4000-8000-000000000000", personal_target: null, input_revision: 0 },
    { user_id: "a0000000-0000-4000-8000-000000000001", personal_target: null, input_revision: 1 },
  ];
  const snapshots = [
    { id: "c0000000-0000-4000-8000-000000000000", user_id: members[0].user_id, value: "42", cutoff_at: "2026-09-03T16:00:00.000Z" },
  ];
  const { database, queries } = mockRecalculateDatabase({ endsAt, members, snapshots });
  await recalculateFight(fightId, new Date("2026-09-05T16:06:35.093Z"), database);
  const payload = queries
    .find(({ query }) => query.includes("update public.fight_members"))
    ?.values.find((value) => JSON.stringify(value).includes('"final_steps_complete"'));
  assert.deepEqual(payload, json([
    { user_id: members[0].user_id, current_value: 42, rank: 1, outcome_minor: 0, final_steps_complete: false },
    { user_id: members[1].user_id, current_value: 0, rank: 1, outcome_minor: 0, final_steps_complete: false },
  ]));
});
