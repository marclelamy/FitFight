import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  healthKitDiagnosticSnapshotResponseSchema,
  type HealthKitDiagnosticSnapshot,
  type HealthKitDiagnosticSnapshotResponse,
} from "@/lib/types/healthkit/healthkit-diagnostic";

export async function saveHealthKitDiagnosticSnapshot(
  userId: string,
  input: HealthKitDiagnosticSnapshot,
  database: Sql = createDatabaseClient(),
): Promise<HealthKitDiagnosticSnapshotResponse> {
  return database.begin("read write", async (sql) => {
    // The snapshot row serializes this user's reports before bounded history is updated.
    const [row] = await sql`
      insert into private.healthkit_sync_diagnostics (
        user_id, connection_route, background_refresh_status,
        delivery_registration_status, last_observer_wake, last_sync_attempt,
        last_automatic_sync, last_manual_sync, last_trigger_context, error_code,
        app_version, app_build, updated_at
      ) values (
        ${userId}, 'healthkit', ${input.background_refresh_status},
        ${input.delivery_registration_status}, ${input.last_observer_wake},
        ${input.last_sync_attempt}, ${input.last_automatic_sync},
        ${input.last_manual_sync}, ${input.last_trigger_context}, ${input.error_code},
        ${input.app_version}, ${input.app_build}, clock_timestamp()
      )
      on conflict (user_id, connection_route) do update
      set background_refresh_status = excluded.background_refresh_status,
        delivery_registration_status = excluded.delivery_registration_status,
        last_observer_wake = excluded.last_observer_wake,
        last_sync_attempt = excluded.last_sync_attempt,
        last_automatic_sync = excluded.last_automatic_sync,
        last_manual_sync = excluded.last_manual_sync,
        last_trigger_context = excluded.last_trigger_context,
        error_code = excluded.error_code,
        app_version = excluded.app_version,
        app_build = excluded.app_build,
        updated_at = excluded.updated_at
      returning to_char(
        updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'
      ) as updated_at
    `;
    if (!row) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not save HealthKit diagnostics");
    }

    if (input.attempts && input.attempts.length > 0) {
      await sql`
        insert into private.healthkit_sync_attempts (
          user_id, attempt_id, trigger, started_at, outcome, error_code, total_ms,
          stages, fight_count, day_count, payload_bytes, app_version, app_build
        )
        select ${userId}, attempt.attempt_id, attempt.trigger, attempt.started_at,
          attempt.outcome, attempt.error_code, attempt.total_ms, attempt.stages,
          attempt.fight_count, attempt.day_count, attempt.payload_bytes,
          ${input.app_version}, ${input.app_build}
        from jsonb_to_recordset(${sql.json(input.attempts)}::jsonb) as attempt (
          attempt_id uuid, trigger text, started_at timestamptz, outcome text,
          error_code text, total_ms double precision, stages jsonb,
          fight_count integer, day_count integer, payload_bytes integer
        )
        on conflict (user_id, attempt_id) do nothing
      `;
    }

    await sql`
      delete from private.healthkit_sync_attempts
      where user_id = ${userId}
        and (
          received_at < clock_timestamp() - interval '7 days'
          or attempt_id in (
            select attempt_id from private.healthkit_sync_attempts
            where user_id = ${userId}
            order by received_at desc, attempt_id desc
            offset 100
          )
        )
    `;
    return healthKitDiagnosticSnapshotResponseSchema.parse(row);
  });
}
