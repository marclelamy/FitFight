import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { insertServerErrorLog } from "@/lib/supabase/queries/server-error-logs-supabase-query";
import { serverErrorLogInsertSchema } from "@/lib/types/observability/server-error-log";

test("server error log inserts go to the private table", async () => {
  const statements: { text: string; values: unknown[] }[] = [];
  const sql = ((strings: TemplateStringsArray, ...values: unknown[]) => {
    statements.push({ text: strings.join("?"), values });
    return Promise.resolve([]);
  }) as unknown as Sql;
  const row = serverErrorLogInsertSchema.parse({
    user_id: "11111111-1111-4111-8111-111111111111",
    method: "POST",
    path: "/api/v1/feedback/dddddddd-dddd-4ddd-8ddd-dddddddddddd/fix-agent",
    action: "POST /api/v1/feedback/:postID/fix-agent",
    route_params: { postID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd" },
    status: 502,
    error_code: "internal",
    failure: "Could not start the Cursor agent. (upstream 502)",
    trace: { name: "ApiError", message: "Could not start the Cursor agent." },
    app_version: "1.0.0",
    app_build: "183",
    request_trace_id: null,
  });
  await insertServerErrorLog(row, sql);
  assert.equal(statements.length, 1);
  assert.match(statements[0]?.text ?? "", /insert into private\.server_error_logs/);
  assert.match(statements[0]?.text ?? "", /::jsonb/);
  assert.equal(statements[0]?.values[0], row.user_id);
  assert.equal(statements[0]?.values[2], row.path);
  assert.equal(statements[0]?.values[7], row.failure);
});
