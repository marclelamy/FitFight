import type { HealthKitDiagnosticSnapshot } from "@/lib/types/healthkit/healthkit-diagnostic";

/** Logs only operational fields from an authenticated, validated diagnostic report. */
export function logHealthKitFailures(input: HealthKitDiagnosticSnapshot) {
  const app = {
    app_version: /^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(input.app_version) ? input.app_version : undefined,
    app_build: /^\d{1,10}$/.test(input.app_build) ? input.app_build : undefined,
  };
  if (input.attempts && input.attempts.length > 0) {
    for (const attempt of input.attempts) {
      if (attempt.outcome === "succeeded") continue;
      console.warn("fitfight_healthkit_failure", JSON.stringify({
        ...app,
        trace_id: attempt.attempt_id,
        trigger: attempt.trigger,
        outcome: attempt.outcome,
        error_code: attempt.error_code,
        stages: attempt.stages
          .filter((stage) => stage.outcome !== "succeeded")
          .map((stage) => ({ stage: stage.stage, outcome: stage.outcome, error: stage.error })),
      }));
    }
  } else if (input.error_code) {
    console.warn("fitfight_healthkit_failure", JSON.stringify({
      ...app, trigger: input.last_trigger_context, error_code: input.error_code,
    }));
  }
}
