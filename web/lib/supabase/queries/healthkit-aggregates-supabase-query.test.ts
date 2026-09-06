import assert from "node:assert/strict";
import { test } from "node:test";
import postgres, { type Sql } from "postgres";
import {
  healthKitAggregateSyncResponseSchema,
  healthKitAggregateSyncSchema,
} from "@/lib/types/healthkit/healthkit-aggregate";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";

const json = postgres().json;

function createDatabaseStub(
  respond: (query: string, values: readonly unknown[]) => unknown[],
) {
  const queries: Array<{ query: string; values: readonly unknown[] }> = [];
  const transaction = ((first: unknown, ...values: unknown[]) => {
    if (!Array.isArray(first) || !("raw" in first)) {
      return { first, values };
    }
    const strings = first as unknown as TemplateStringsArray;
    const query = strings.join("?");
    queries.push({ query, values });
    return Promise.resolve(respond(query, values));
  }) as unknown as Sql;
  Object.assign(transaction, { array: (values: readonly unknown[]) => values, json });
  const database = Object.assign(
    (() => Promise.reject(new Error("query must run inside a transaction"))) as unknown as Sql,
    {
      begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) =>
        callback(transaction),
    },
  );
  return { database, queries };
}

const validAggregate = {
  complete_through: "2026-08-30T13:53:27.350Z",
  time_zone: "Europe/Paris",
  merged_days: [{
    day: "2026-08-30",
    starts_at: "2026-08-29T22:00:00.000Z",
    ends_at: "2026-08-30T13:53:27.350Z",
    steps: 12_345,
  }],
  fight_aggregates: [{
    fight_id: "B4C1285D-0232-4D15-B8CC-1A916BA2BBF7",
    starts_at: "2026-08-27T16:06:36.729Z",
    ends_at: "2026-09-03T16:06:35.093Z",
    cutoff_at: "2026-08-30T13:53:27.350Z",
    steps: 42_000,
  }],
};
const sourceRow = {
  id: "333822a8-8577-4d9d-8145-ab5f120ee42f",
  complete_through: validAggregate.complete_through,
  server_now: "2026-08-30T14:00:00.000Z",
};

test("Apple Health aggregate sync accepts one merged total per Fight", () => {
  const parsed = healthKitAggregateSyncSchema.parse(validAggregate);

  assert.equal(parsed.time_zone, "Europe/Paris");
  assert.equal(parsed.merged_days[0]?.steps, 12_345);
  assert.equal(parsed.fight_aggregates[0]?.fight_id, "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7");
  assert.equal(parsed.fight_aggregates[0]?.steps, 42_000);
});

test("Apple Health aggregate sync rejects raw HealthKit records", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    samples: [{ sample_id: "333822a8-8577-4d9d-8145-ab5f120ee42f" }],
  }));
});

test("Apple Health aggregate sync requires the server-authoritative cutoff", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    fight_aggregates: [{
      ...validAggregate.fight_aggregates[0],
      cutoff_at: "2026-08-30T12:00:00.000Z",
    }],
  }), /cutoff_at does not match complete_through/);
});

test("Apple Health aggregate sync rejects an invalid merged-day range", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [{
      ...validAggregate.merged_days[0],
      ends_at: validAggregate.merged_days[0].starts_at,
    }],
  }), /ends_at must follow starts_at/);
});

test("Apple Health aggregate sync rejects duplicate merged days", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [validAggregate.merged_days[0], validAggregate.merged_days[0]],
  }), /duplicate merged day/);
});

test("Apple Health aggregate sync rejects a merged day beyond complete_through", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [{
      ...validAggregate.merged_days[0],
      ends_at: "2026-08-30T22:00:00.000Z",
    }],
  }), /ends_at exceeds complete_through/);
});

test("Apple Health aggregate sync requires complete civil-day bounds", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [{
      ...validAggregate.merged_days[0],
      ends_at: "2026-08-30T13:00:00.000Z",
    }],
  }), /ends_at must equal the effective civil-day end/);
});

test("Apple Health aggregate sync rejects duplicate Fights and invalid time zones", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    fight_aggregates: [validAggregate.fight_aggregates[0], validAggregate.fight_aggregates[0]],
  }), /duplicate Fight aggregate/);
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    time_zone: "Mars/Olympus_Mons",
  }), /invalid time zone/);
});

test("Apple Health aggregate sync bounds aggregate counts", () => {
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: Array.from({ length: 401 }, () => validAggregate.merged_days[0]),
  }), /at most 400/);
  assert.throws(() => healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    fight_aggregates: Array.from(
      { length: 101 },
      () => validAggregate.fight_aggregates[0],
    ),
  }), /at most 100/);
});

test("Apple Health aggregate upload query count stays bounded across fights and rosters", async () => {
  const statementCounts: number[] = [];
  const userId = "5b2216f4-762d-4890-a516-63046a01df31";
  for (const [fightCount, memberCount] of [[1, 2], [5, 20]]) {
    const input = healthKitAggregateSyncSchema.parse({
      ...validAggregate,
      fight_aggregates: Array.from({ length: fightCount }, (_, index) => ({
        ...validAggregate.fight_aggregates[0],
        fight_id: `b4c1285d-0232-4d15-b8cc-${String(index).padStart(12, "0")}`,
      })),
    });
    const fights = input.fight_aggregates.map((aggregate) => ({
      fight_id: aggregate.fight_id,
      starts_at: aggregate.starts_at,
      ends_at: aggregate.ends_at,
      outcome_rule: "highest_total",
      stake_minor: null,
      default_goal_value: null,
    }));
    const { database, queries } = createDatabaseStub((query, values) => {
      if (query.includes("returning id, complete_through")) return [sourceRow];
      if (query.includes("from public.fights as fight")) return fights;
      if (query.includes("from private.fight_score_snapshots")) {
        return fights.map((fight) => ({ fight_id: fight.fight_id, value: "42000" }));
      }
      if (query.includes("from public.fight_members") && query.includes("state = 'accepted'")) {
        const requestedFights = fights.filter((fight) => values.includes(fight.fight_id));
        return (requestedFights.length ? requestedFights : fights).flatMap((fight) =>
          Array.from({ length: memberCount }, (_, index) => ({
            fight_id: fight.fight_id,
            user_id: index === 0 ? userId : `a0000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
            current_value: String(42_000 - index),
            final_value: null,
            personal_target: null,
          }))
        );
      }
      return [];
    });

    const result = await syncHealthKitAggregates(userId, input, database);
    assert.equal(result.synced_fights, fightCount);
    statementCounts.push(queries.length);
    const rankUpdates = queries.filter(({ query }) => query.includes("set rank"));
    assert.equal(rankUpdates.length, 1);
    const rankPayload = rankUpdates[0].values[0];
    assert.deepEqual(rankPayload, json(fights.flatMap((fight) =>
      Array.from({ length: memberCount }, (_, index) => ({
        fight_id: fight.fight_id,
        user_id: index === 0 ? userId : `a0000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
        rank: index + 1,
        outcome_minor: 0,
      }))
    )));
  }

  assert.equal(statementCounts[1], statementCounts[0], "fight and roster size must not add database round trips");
  assert.ok(statementCounts.every((count) => count <= 8), `expected at most 8 statements, got ${statementCounts}`);
});

test("Apple Health aggregate sync records an empty successful sync transaction", async () => {
  const { database, queries } = createDatabaseStub((query) =>
    query.includes("returning id") ? [sourceRow] : []
  );
  const input = healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [],
    fight_aggregates: [],
  });

  const result = await syncHealthKitAggregates(
    "5b2216f4-762d-4890-a516-63046a01df31",
    input,
    database,
  );

  assert.deepEqual(result, {
    complete_through: "2026-08-30T13:53:27.350Z",
    synced_days: 0,
    synced_fights: 0,
  });
  assert.deepEqual(healthKitAggregateSyncResponseSchema.parse(result), result);
  assert.ok(queries.some(({ query }) => query.includes("insert into public.data_sources")));
});

test("Apple Health aggregate sync rejects future complete_through values", async () => {
  const futureCompleteThrough = "2026-08-30T15:00:00.000Z";
  const { database } = createDatabaseStub((query) =>
    query.includes("returning id") ? [{
      ...sourceRow,
      complete_through: futureCompleteThrough,
    }] : []
  );
  const input = healthKitAggregateSyncSchema.parse({
    complete_through: futureCompleteThrough,
    time_zone: "Europe/Paris",
    merged_days: [],
    fight_aggregates: [],
  });

  await assert.rejects(
    syncHealthKitAggregates("5b2216f4-762d-4890-a516-63046a01df31", input, database),
    /complete_through cannot be in the future/,
  );
});

test("Apple Health aggregate sync rejects a stale checkpoint", async () => {
  const { database } = createDatabaseStub((query) =>
    query.includes("returning id") ? [{
      ...sourceRow,
      complete_through: "2026-08-30T13:59:00.000Z",
    }] : []
  );
  const input = healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [],
    fight_aggregates: [],
  });

  await assert.rejects(
    syncHealthKitAggregates("5b2216f4-762d-4890-a516-63046a01df31", input, database),
    /Sync is older than current Apple Health data/,
  );
});

test("Apple Health aggregate sync requires every server-context Fight", async () => {
  const { database } = createDatabaseStub((query) => {
    if (query.includes("returning id")) {
      return [sourceRow];
    }
    if (query.includes("from public.fights as fight")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27 16:06:36.729+00",
        ends_at: "2026-09-03 16:06:35.093+00",
        outcome_rule: "highest_total",
        stake_minor: null,
        default_goal_value: null,
      }];
    }
    return [];
  });
  const input = healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [],
    fight_aggregates: [],
  });

  await assert.rejects(
    syncHealthKitAggregates("5b2216f4-762d-4890-a516-63046a01df31", input, database),
    /Fight aggregate set does not match sync context/,
  );
});

test("Apple Health aggregate sync rejects a Fight window that differs from the server", async () => {
  const { database } = createDatabaseStub((query) => {
    if (query.includes("returning id")) {
      return [sourceRow];
    }
    if (query.includes("from public.fights as fight")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27 15:06:36.729+00",
        ends_at: "2026-09-03 16:06:35.093+00",
        outcome_rule: "highest_total",
        stake_minor: null,
        default_goal_value: null,
      }];
    }
    return [];
  });
  const input = healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [],
  });

  await assert.rejects(
    syncHealthKitAggregates("5b2216f4-762d-4890-a516-63046a01df31", input, database),
    /Fight aggregate does not match sync context/,
  );
});

test("Apple Health aggregate sync rejects merged days outside submitted Fights", async () => {
  const { database } = createDatabaseStub((query) => {
    if (query.includes("returning id")) {
      return [sourceRow];
    }
    if (query.includes("from public.fights as fight")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27 16:06:36.729+00",
        ends_at: "2026-09-03 16:06:35.093+00",
        outcome_rule: "highest_total",
        stake_minor: null,
        default_goal_value: null,
      }];
    }
    return [];
  });
  const input = healthKitAggregateSyncSchema.parse({
    ...validAggregate,
    merged_days: [{
      day: "2026-08-25",
      starts_at: "2026-08-24T22:00:00.000Z",
      ends_at: "2026-08-25T22:00:00.000Z",
      steps: 9_000,
    }],
  });

  await assert.rejects(
    syncHealthKitAggregates("5b2216f4-762d-4890-a516-63046a01df31", input, database),
    /Merged day does not overlap a submitted Fight/,
  );
});

test("Apple Health aggregate sync writes merged days without raw observations", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("returning id")) {
      return [sourceRow];
    }
    if (query.includes("from public.fights as fight")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27 16:06:36.729+00",
        ends_at: "2026-09-03 16:06:35.093+00",
        outcome_rule: "highest_total",
        stake_minor: null,
        default_goal_value: null,
      }];
    }
    if (query.includes("from private.fight_score_snapshots")) {
      return [{ fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7" }];
    }
    if (query.includes("from public.fight_members") && query.includes("state = 'accepted'")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        user_id: "5b2216f4-762d-4890-a516-63046a01df31",
        current_value: "42000",
        final_value: null,
        personal_target: null,
      }];
    }
    return [];
  });

  await syncHealthKitAggregates(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitAggregateSyncSchema.parse(validAggregate),
    database,
  );

  assert.ok(queries.some(({ query }) => query.includes("insert into public.metric_days")));
  assert.ok(queries.some(({ query }) => query.includes("insert into public.step_days")));
  assert.ok(queries.every(({ query }) => !query.includes("metric_observations")));
  assert.ok(queries.every(({ query }) => !query.includes("provider_events")));
});

test("Apple Health aggregate sync makes the newest Fight snapshot authoritative without finalizing", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("returning id, complete_through")) {
      return [sourceRow];
    }
    if (query.includes("from public.fights as fight")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27 16:06:36.729+00",
        ends_at: "2026-09-03 16:06:35.093+00",
        outcome_rule: "highest_total",
        stake_minor: null,
        default_goal_value: null,
      }];
    }
    if (query.includes("from private.fight_score_snapshots")
      && query.includes("order by fight_id, cutoff_at desc")) {
      return [{ fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7" }];
    }
    if (query.includes("from public.fight_members") && query.includes("state = 'accepted'")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        user_id: "5b2216f4-762d-4890-a516-63046a01df31",
        current_value: "42000",
        final_value: null,
        personal_target: null,
      }];
    }
    return [];
  });

  const result = await syncHealthKitAggregates(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitAggregateSyncSchema.parse({ ...validAggregate, merged_days: [] }),
    database,
  );

  assert.equal(result.synced_fights, 1);
  assert.ok(queries.some(({ query }) => query.includes("insert into private.fight_score_snapshots")));
  assert.ok(queries.some(({ query }) =>
    query.includes("set current_value")
      && query.includes("selected_source_id")
      && query.includes("last_synced_at")
      && query.includes("final_steps_complete")
  ));
  const memberUpdate = queries.find(({ query }) => query.includes("set current_value"));
  assert.ok(memberUpdate?.values.some((value) =>
    JSON.stringify(value).includes('"final_steps_complete":false')
  ));
  assert.ok(queries.some(({ query }) => query.includes("set rank")));
  assert.ok(queries.every(({ query }) => !/set\s+final_value/i.test(query)));
});

test("Apple Health aggregate sync marks exact Fight-end coverage complete", async () => {
  const completeThrough = "2026-09-03T16:06:35.093Z";
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("returning id, complete_through")) {
      return [{ ...sourceRow, complete_through: completeThrough, server_now: "2026-09-03T17:00:00.000Z" }];
    }
    if (query.includes("from public.fights as fight")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27 16:06:36.729+00",
        ends_at: "2026-09-03 16:06:35.093+00",
        outcome_rule: "highest_total",
        stake_minor: null,
        default_goal_value: null,
      }];
    }
    if (query.includes("from private.fight_score_snapshots")) {
      return [{ fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7" }];
    }
    if (query.includes("from public.fight_members") && query.includes("state = 'accepted'")) {
      return [{
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        user_id: "5b2216f4-762d-4890-a516-63046a01df31",
        current_value: "50000",
        final_value: null,
        personal_target: null,
      }];
    }
    return [];
  });

  await syncHealthKitAggregates(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitAggregateSyncSchema.parse({
      ...validAggregate,
      complete_through: completeThrough,
      merged_days: [],
      fight_aggregates: [{
        ...validAggregate.fight_aggregates[0],
        cutoff_at: completeThrough,
        steps: 50_000,
      }],
    }),
    database,
  );

  const memberUpdate = queries.find(({ query }) => query.includes("set current_value"));
  assert.ok(memberUpdate?.values.some((value) =>
    JSON.stringify(value).includes('"final_steps_complete":true')
  ));
});

test("Apple Health Steps endpoint exposes the authenticated sync route", async () => {
  const route = await import("@/app/api/v1/healthkit/steps/route");

  assert.equal(route.runtime, "nodejs");
  assert.equal(typeof route.POST, "function");
  assert.equal(typeof route.OPTIONS, "function");
});

test("HealthKit diagnostics endpoint exposes the authenticated snapshot route", async () => {
  const route = await import("@/app/api/v1/healthkit/diagnostics/route");

  assert.equal(route.runtime, "nodejs");
  assert.equal(typeof route.POST, "function");
  assert.equal(typeof route.OPTIONS, "function");

  const response = await route.POST(
    new Request("https://fitfight.app/api/v1/healthkit/diagnostics", { method: "POST" }),
    { params: Promise.resolve({}) },
  );
  assert.equal(response.status, 401);
  assert.equal((await response.json()).code, "unauthorized");
});
