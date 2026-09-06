import assert from "node:assert/strict";
import test from "node:test";
import postgres, { type Sql } from "postgres";
import { saveHealthKitDiagnosticSnapshot } from "@/lib/supabase/queries/healthkit-diagnostics-supabase-query";
import {
  healthKitDiagnosticSnapshotResponseSchema,
  healthKitDiagnosticSnapshotSchema,
  healthKitSyncAttemptSchema,
} from "@/lib/types/healthkit/healthkit-diagnostic";

const validSnapshot = {
  background_refresh_status: "available",
  delivery_registration_status: "enabled",
  last_observer_wake: "2026-09-04T08:00:00.000Z",
  last_sync_attempt: "2026-09-04T08:00:01.000Z",
  last_automatic_sync: "2026-09-04T08:00:02.000Z",
  last_manual_sync: null,
  last_trigger_context: "observer",
  error_code: null,
  app_version: "1.0.0",
  app_build: "42",
} as const;

const validAttempt = {
  attempt_id: "abb67989-c67f-4c5a-84a1-b26d728712f7",
  trigger: "foreground",
  started_at: "2026-09-05T08:00:00Z",
  outcome: "succeeded",
  total_ms: 482.25,
  stages: [
    { stage: "healthkit_daily", started_ms: 45, duration_ms: 30, outcome: "succeeded" },
    {
      stage: "upload", started_ms: 120, duration_ms: 220, outcome: "succeeded",
      server_timing: { auth_ms: 12, db_ms: 25, total_ms: 39 },
    },
    { stage: "fights_refresh", started_ms: 340, duration_ms: 142.25, outcome: "succeeded" },
  ],
  fight_count: 2,
  day_count: 7,
  payload_bytes: 1_240,
};

const json = postgres().json;

function recordingDatabase(statements: { text: string; values: unknown[] }[]): Sql {
  const sql = ((strings: TemplateStringsArray, ...values: unknown[]) => {
    const text = strings.join("?");
    statements.push({ text, values });
    return Promise.resolve(text.includes("returning to_char")
      ? [{ updated_at: "2026-09-05T08:00:03Z" }]
      : []);
  }) as unknown as Sql;
  sql.begin = ((_mode: string, callback: (transaction: Sql) => Promise<unknown>) =>
    callback(sql)) as Sql["begin"];
  sql.json = json;
  return sql;
}

test("HealthKit diagnostics accept only the stable snapshot vocabulary", () => {
  assert.deepEqual(healthKitDiagnosticSnapshotSchema.parse(validSnapshot), validSnapshot);
  assert.throws(() => healthKitDiagnosticSnapshotSchema.parse({
    ...validSnapshot,
    background_refresh_status: "sometimes",
  }));
  assert.throws(() => healthKitDiagnosticSnapshotSchema.parse({
    ...validSnapshot,
    free_form_error: "private device details",
  }));
});

test("HealthKit diagnostics accept the omitted nil fields emitted by native Codable", () => {
  assert.deepEqual(healthKitDiagnosticSnapshotSchema.parse({
    background_refresh_status: "available",
    delivery_registration_status: "enabled",
    app_version: "1.0.0",
    app_build: "42",
  }), {
    background_refresh_status: "available",
    delivery_registration_status: "enabled",
    last_observer_wake: null,
    last_sync_attempt: null,
    last_automatic_sync: null,
    last_manual_sync: null,
    last_trigger_context: null,
    error_code: null,
    app_version: "1.0.0",
    app_build: "42",
  });
});

test("HealthKit attempt timings preserve fractional elapsed time and server durations", () => {
  assert.deepEqual(healthKitSyncAttemptSchema.parse(validAttempt), validAttempt);
  for (const outcome of ["failed", "cancelled"]) {
    const partialAttempt = {
      ...validAttempt,
      outcome,
      error_code: "attempt_expired",
      stages: [{
        stage: "healthkit_daily", started_ms: 45, duration_ms: 25_000, outcome,
      }],
      total_ms: 25_045,
    };
    assert.deepEqual(healthKitSyncAttemptSchema.parse(partialAttempt), partialAttempt);
  }
});

test("HealthKit timing boundaries reject invalid durations, counts and unknown fields", () => {
  for (const value of [-1, Number.NaN, Number.POSITIVE_INFINITY, 604_800_001]) {
    assert.throws(() => healthKitSyncAttemptSchema.parse({ ...validAttempt, total_ms: value }));
    assert.throws(() => healthKitSyncAttemptSchema.parse({
      ...validAttempt,
      stages: [{ stage: "upload", started_ms: 0, duration_ms: value, outcome: "succeeded" }],
    }));
    assert.throws(() => healthKitSyncAttemptSchema.parse({
      ...validAttempt,
      stages: [{
        stage: "upload", started_ms: 0, duration_ms: 1, outcome: "succeeded",
        server_timing: { total_ms: value },
      }],
    }));
  }
  for (const invalid of [
    { fight_count: 101 }, { day_count: 401 }, { payload_bytes: 1_000_001 },
    { fight_count: 0.5 }, { attempt_id: "not-a-uuid" }, { trigger: "unknown" },
    { outcome: "unknown" }, { raw_steps: 1_234 }, { user_id: "another-user" },
    { error_code: "free form device error" },
    { stages: [{ ...validAttempt.stages[0], fight_id: "private-fight" }] },
    { stages: [{ ...validAttempt.stages[0], stage: "unknown" }] },
    { stages: [{ ...validAttempt.stages[0], server_timing: { query: "select private data" } }] },
    { stages: Array.from({ length: 257 }, () => validAttempt.stages[0]) },
  ]) {
    assert.throws(() => healthKitSyncAttemptSchema.parse({ ...validAttempt, ...invalid }));
  }
  assert.throws(() => healthKitDiagnosticSnapshotSchema.parse({
    ...validSnapshot,
    attempts: Array.from({ length: 11 }, () => validAttempt),
  }));
});

test("HealthKit diagnostics retain legacy snapshot reports and prune only their user", async () => {
  const statements: { text: string; values: unknown[] }[] = [];
  const database = recordingDatabase(statements);

  const result = await saveHealthKitDiagnosticSnapshot(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitDiagnosticSnapshotSchema.parse(validSnapshot),
    database,
  );

  assert.equal(statements.length, 2);
  assert.match(statements[0].text, /on conflict \(user_id, connection_route\) do update/);
  assert.match(statements[1].text, /delete from private.healthkit_sync_attempts/);
  assert.match(statements[1].text, /interval '7 days'/);
  assert.match(statements[1].text, /order by received_at desc, attempt_id desc\s+offset 100/);
  assert.deepEqual(statements[1].values, [
    "5b2216f4-762d-4890-a516-63046a01df31", "5b2216f4-762d-4890-a516-63046a01df31",
  ]);
  assert.deepEqual(healthKitDiagnosticSnapshotResponseSchema.parse(result), result);
});

test("HealthKit diagnostics batch attempt inserts with authenticated ownership and deduplication", async () => {
  const statements: { text: string; values: unknown[] }[] = [];
  const database = recordingDatabase(statements);
  const attempts = [validAttempt, {
    ...validAttempt, attempt_id: "a8263691-af86-4119-83dc-a5aa34a7283d",
  }];

  await saveHealthKitDiagnosticSnapshot(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitDiagnosticSnapshotSchema.parse({ ...validSnapshot, attempts }),
    database,
  );

  assert.equal(statements.length, 3);
  assert.match(statements[1].text, /insert into private.healthkit_sync_attempts/);
  assert.match(statements[1].text, /on conflict \(user_id, attempt_id\) do nothing/);
  assert.deepEqual(statements[1].values, [
    "5b2216f4-762d-4890-a516-63046a01df31", "1.0.0", "42", json(attempts),
  ]);
});
