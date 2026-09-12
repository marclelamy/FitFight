import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { ServerErrorLogInsert } from "@/lib/types/observability/server-error-log";

export async function insertServerErrorLog(
  row: ServerErrorLogInsert,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  await database`
    insert into private.server_error_logs (
      user_id, method, path, action, route_params,
      status, error_code, failure, trace,
      app_version, app_build, request_trace_id
    ) values (
      ${row.user_id}, ${row.method}, ${row.path}, ${row.action},
      ${JSON.stringify(row.route_params)}::jsonb,
      ${row.status}, ${row.error_code}, ${row.failure},
      ${JSON.stringify(row.trace)}::jsonb,
      ${row.app_version}, ${row.app_build}, ${row.request_trace_id}
    )
  `;
}
