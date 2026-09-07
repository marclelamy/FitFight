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
    assert.equal(memberUpdates[0].values.filter((value) => value === true).length, 2,
      "both final value and finalized_at must freeze");
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
  assert.ok(statementCounts.every((count) => count <= 6), `expected at most 6 statements, got ${statementCounts}`);
});
