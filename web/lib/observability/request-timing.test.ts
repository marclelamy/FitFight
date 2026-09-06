import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError, apiRoute, json, measureRequestStage } from "@/lib/http";

test("timed requests return measured phases and log no request payloads or credentials", async (t) => {
  const log = t.mock.method(console, "info", () => {});
  const ticks = [0, 5, 15, 20];
  t.mock.method(performance, "now", () => ticks.shift()!);
  const route = apiRoute(async (_request, { timing }) => {
    await measureRequestStage(timing, "auth", async () => {});
    return json({ ok: true });
  }, "healthkit_upload");
  const traceId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const response = await route(new Request("https://fitfight.app/api/v1/healthkit/steps?secret=private-query", {
    method: "POST", body: "private-health-payload",
    headers: { Authorization: "Bearer test-credential", "X-FitFight-Trace-ID": traceId },
  }), { params: Promise.resolve({}) });
  assert.equal(response.headers.get("Server-Timing"), "auth;dur=10.0, total;dur=20.0");
  assert.equal(response.headers.get("X-FitFight-Trace-ID"), traceId);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(log.mock.callCount(), 1);
  assert.deepEqual(JSON.parse(log.mock.calls[0].arguments[1]), {
    operation: "healthkit_upload", trace_id: traceId, status: 200,
    durations_ms: { auth: 10, total: 20 },
  });
});

test("failed phases keep timing headers and invalid trace identifiers cannot enter logs", async (t) => {
  const log = t.mock.method(console, "info", () => {});
  const route = apiRoute(async (_request, { timing }) => {
    return measureRequestStage(timing, "db", async () => {
      throw new ApiError(409, "conflict", "Sync changed");
    });
  }, "healthkit_upload");
  const response = await route(new Request("https://fitfight.app/api/v1/healthkit/steps", {
    headers: { "X-FitFight-Trace-ID": "untrusted-user-text" },
  }), { params: Promise.resolve({}) });
  assert.equal(response.status, 409);
  assert.match(response.headers.get("X-FitFight-Trace-ID") ?? "", /^[0-9a-f-]{36}$/);
  assert.match(response.headers.get("Server-Timing") ?? "", /db;dur=[\d.]+, total;dur=[\d.]+/);
  assert.ok(!JSON.stringify(log.mock.calls[0].arguments).includes("untrusted-user-text"));
});
