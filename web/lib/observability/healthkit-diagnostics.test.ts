import assert from "node:assert/strict";
import { test } from "node:test";
import { logHealthKitFailures } from "@/lib/observability/healthkit-diagnostics";
import { healthKitDiagnosticSnapshotSchema } from "@/lib/types/healthkit/healthkit-diagnostic";

const snapshot = {
  background_refresh_status: "available",
  delivery_registration_status: "enabled",
  app_version: "1.0.0",
  app_build: "153",
};

test("HealthKit failure logs correlate the failing stage without logging health context", (t) => {
  const log = t.mock.method(console, "warn", () => {});
  logHealthKitFailures(healthKitDiagnosticSnapshotSchema.parse({
    ...snapshot, attempts: [{
      attempt_id: "abb67989-c67f-4c5a-84a1-b26d728712f7",
      trigger: "manual", started_at: "2026-09-05T08:00:00Z",
      outcome: "failed", error_code: "sync_failed", total_ms: 400,
      fight_count: 2, day_count: 7, payload_bytes: 1240,
      stages: [
        { stage: "context", started_ms: 0, duration_ms: 300, outcome: "succeeded" },
        {
          stage: "healthkit_fight", started_ms: 300, duration_ms: 100,
          outcome: "failed", error: { kind: "healthkit", code: 11 },
        },
      ],
    }],
  }));
  assert.equal(log.mock.callCount(), 1);
  assert.equal(log.mock.calls[0].arguments[0], "fitfight_healthkit_failure");
  assert.deepEqual(JSON.parse(log.mock.calls[0].arguments[1]), {
    app_version: "1.0.0", app_build: "153",
    trace_id: "abb67989-c67f-4c5a-84a1-b26d728712f7",
    trigger: "manual", outcome: "failed", error_code: "sync_failed",
    stages: [{ stage: "healthkit_fight", outcome: "failed", error: { kind: "healthkit", code: 11 } }],
  });
});

test("legacy HealthKit failures are visible and free-form version strings stay out of logs", (t) => {
  const log = t.mock.method(console, "warn", () => {});
  logHealthKitFailures(healthKitDiagnosticSnapshotSchema.parse({
    ...snapshot, app_version: "private-device-text", app_build: "private-account-text",
    error_code: "sync_failed", last_trigger_context: "foreground",
  }));
  assert.equal(log.mock.callCount(), 1);
  assert.deepEqual(JSON.parse(log.mock.calls[0].arguments[1]), {
    trigger: "foreground", error_code: "sync_failed",
  });
});

test("successful HealthKit diagnostics do not emit failure logs", (t) => {
  const log = t.mock.method(console, "warn", () => {});
  logHealthKitFailures(healthKitDiagnosticSnapshotSchema.parse(snapshot));
  logHealthKitFailures(healthKitDiagnosticSnapshotSchema.parse({
    ...snapshot, attempts: [{
      attempt_id: "abb67989-c67f-4c5a-84a1-b26d728712f7",
      trigger: "manual", started_at: "2026-09-05T08:00:00Z",
      outcome: "succeeded", total_ms: 400, stages: [],
    }],
  }));
  assert.equal(log.mock.callCount(), 0);
});
