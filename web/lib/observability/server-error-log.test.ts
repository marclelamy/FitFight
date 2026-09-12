import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError, apiRoute } from "@/lib/http";
import {
  redactSecrets,
  recordApiFailure,
  serverErrorLogEntry,
  setServerErrorLogWriter,
} from "@/lib/observability/server-error-log";
import type { ServerErrorLogInsert } from "@/lib/types/observability/server-error-log";

const userId = "11111111-1111-4111-8111-111111111111";
const postId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

function jwtFor(sub: string): string {
  return `eyJhbGciOiJub25lIn0.${Buffer.from(JSON.stringify({ sub }), "utf8").toString("base64url")}.sig`;
}

test("4xx API errors are not persisted", () => {
  const row = serverErrorLogEntry(new ApiError(409, "conflict", "Sync changed"), {
    request: new Request("https://fitfight.app/api/v1/healthkit/steps"),
    params: {},
    status: 409,
  });
  assert.equal(row, null);
});

test("missing database columns are stored with the Postgres message, route, and user", () => {
  const error = Object.assign(
    new Error('column "final_value_v2" of relation "fight_members" does not exist'),
    { name: "PostgresError", code: "42703", table_name: "fight_members", column_name: "final_value_v2" },
  );
  const row = serverErrorLogEntry(error, {
    request: new Request(`https://fitfight.app/api/v1/feedback/${postId}/fix-agent`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwtFor(userId)}`,
        "X-FitFight-Version": "1.0.0",
        "X-FitFight-Build": "183",
        "X-FitFight-Trace-ID": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      },
    }),
    params: { postID: postId },
    status: 500,
  });
  assert.ok(row);
  assert.equal(row.user_id, userId);
  assert.equal(row.method, "POST");
  assert.equal(row.path, `/api/v1/feedback/${postId}/fix-agent`);
  assert.equal(row.action, "POST /api/v1/feedback/:postID/fix-agent");
  assert.equal(row.error_code, "internal");
  assert.equal(row.failure, 'column "final_value_v2" of relation "fight_members" does not exist');
  assert.equal(row.app_version, "1.0.0");
  assert.equal(row.app_build, "183");
  assert.equal(row.request_trace_id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
  assert.deepEqual(row.route_params, { postID: postId });
  assert.equal(row.trace.column_name, undefined);
  assert.deepEqual(row.trace.postgres, {
    code: "42703",
    table_name: "fight_members",
    column_name: "final_value_v2",
    message: 'column "final_value_v2" of relation "fight_members" does not exist',
  });
});

test("Cursor upstream failures keep the short API message and store the 502 body", () => {
  const error = new ApiError(502, "internal", "Could not start the Cursor agent.", {
    upstream: { status: 502, body: { message: "cloud agents unavailable" } },
  });
  const row = serverErrorLogEntry(error, {
    request: new Request(`https://fitfight.app/api/v1/feedback/${postId}/fix-agent`, { method: "POST" }),
    params: { postID: postId },
    status: 502,
  });
  assert.ok(row);
  assert.equal(row.failure, "Could not start the Cursor agent. (upstream 502)");
  assert.equal(row.error_code, "internal");
  assert.deepEqual(row.trace.detail, {
    upstream: { status: 502, body: { message: "cloud agents unavailable" } },
  });
});

test("secret values never enter the stored trace", () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = "cursor_live_secret_value";
  try {
    const redacted = redactSecrets({
      Authorization: "Bearer super-secret-token",
      note: "key=cursor_live_secret_value sb_secret_abc123",
      pem: "-----BEGIN PRIVATE KEY-----\nABC\n-----END PRIVATE KEY-----",
    });
    assert.deepEqual(redacted, {
      Authorization: "[redacted]",
      note: "key=[redacted] [redacted]",
      pem: "[redacted-pem]",
    });
  } finally {
    if (previous === undefined) delete process.env.CURSOR_API_KEY;
    else process.env.CURSOR_API_KEY = previous;
  }
});

test("apiRoute persists 5xx failures and still returns the short client body", async () => {
  const writes: ServerErrorLogInsert[] = [];
  setServerErrorLogWriter(async (row) => {
    writes.push(row);
  });
  const originalError = console.error.bind(console);
  console.error = () => {};
  try {
    const route = apiRoute(async () => {
      throw new Error("boom");
    });
    const response = await route(new Request("https://fitfight.app/api/v1/fights", { method: "POST" }), {
      params: Promise.resolve({}),
    });
    assert.equal(response.status, 500);
    assert.deepEqual(await response.json(), { error: "Internal error", code: "internal" });
    assert.equal(writes.length, 1);
    assert.equal(writes[0]?.failure, "boom");
    assert.equal(writes[0]?.action, "POST /api/v1/fights");
  } finally {
    console.error = originalError;
    setServerErrorLogWriter(null);
  }
});

test("apiRoute does not persist 4xx failures", async () => {
  const writes: ServerErrorLogInsert[] = [];
  setServerErrorLogWriter(async (row) => {
    writes.push(row);
  });
  try {
    const route = apiRoute(async () => {
      throw new ApiError(409, "conflict", "Sync changed");
    });
    const response = await route(new Request("https://fitfight.app/api/v1/healthkit/steps"), {
      params: Promise.resolve({}),
    });
    assert.equal(response.status, 409);
    assert.equal(writes.length, 0);
    await recordApiFailure(new Request("https://fitfight.app/api/v1/healthkit/steps"), new ApiError(409, "conflict", "Sync changed"), {
      params: {},
      status: 409,
    });
    assert.equal(writes.length, 0);
  } finally {
    setServerErrorLogWriter(null);
  }
});
