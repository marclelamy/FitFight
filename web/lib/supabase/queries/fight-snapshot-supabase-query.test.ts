import assert from "node:assert/strict";
import { test } from "node:test";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";
import { closeDueFightsForUser } from "./close-due-fights-supabase-query";
import { fightSnapshotRequestSchema, fightSnapshotSchema } from "@/lib/types/fights/fight-snapshot";

test("snapshot validates the requested timezone and returns five empty arrays", () => {
  assert.deepEqual(fightSnapshotRequestSchema.parse({ time_zone: "Europe/Paris" }), { time_zone: "Europe/Paris" });
  assert.equal(fightSnapshotRequestSchema.safeParse({ time_zone: "Mars/Olympus" }).success, false);
  assert.equal(fightSnapshotRequestSchema.safeParse({ time_zone: "UTC", user_id: "someone-else" }).success, false);
  assert.deepEqual(fightSnapshotSchema.parse({ fights: [], members: [], profiles: [], series: [], step_days: [] }),
    { fights: [], members: [], profiles: [], series: [], step_days: [] });
});

test("snapshot establishes transaction-local caller permissions before its single data query", async () => {
  const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const snapshot = { fights: [], members: [], profiles: [], series: [], step_days: [] };
  const calls: Array<{ query: string; values: unknown[] }> = [];
  const sql = async (strings: TemplateStringsArray, ...values: unknown[]) => {
    const query = strings.join("?");
    calls.push({ query, values });
    return query.includes("as snapshot") ? [{ snapshot }] : [];
  };
  const database = {
    begin: async (options: string, callback: (transaction: typeof sql) => Promise<unknown>) => {
      assert.equal(options, "read only");
      return callback(sql);
    },
  };
  assert.deepEqual(await readFightSnapshot(userId, "Europe/Paris", database as never), snapshot);
  assert.equal(calls.length, 3);
  assert.equal(calls[0].query, "set local role authenticated");
  assert.ok(calls[1].query.includes("set_config('request.jwt.claim.sub', ?, true)"));
  assert.deepEqual(calls[1].values, [userId, JSON.stringify({ sub: userId, role: "authenticated" })]);
  assert.ok(calls[2].values.includes("Europe/Paris"));
});

test("ordinary maintenance uses one database query and never scans unrelated series over REST", async () => {
  const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const now = new Date("2026-09-05T12:00:00Z");
  let statements = 0;
  const database = async (_strings: TemplateStringsArray, ...values: unknown[]) => {
    statements++;
    assert.ok(values.includes(userId));
    return [{ candidates: [{
      id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", state: "live",
      starts_at: "2026-09-04T12:00:00Z", ends_at: "2026-09-07T12:00:00Z",
    }], recurring: [] }];
  };
  const admin = { from: () => { throw new Error("ordinary refresh must not scan REST tables"); } };
  assert.deepEqual(await closeDueFightsForUser(userId, admin as never, now, database as never),
    { checked: 1, closed: 0, fightIds: [] });
  assert.equal(statements, 1);
});

test("refresh endpoint rejects unauthenticated requests before maintenance and emits timing", async () => {
  const { POST } = await import("@/app/api/v1/fights/refresh/route");
  const traceId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const response = await POST(new Request("https://fitfight.app/api/v1/fights/refresh", {
    method: "POST", headers: { "X-FitFight-Trace-ID": traceId },
  }), { params: Promise.resolve({}) });
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("X-FitFight-Trace-ID"), traceId);
  assert.match(response.headers.get("Server-Timing") ?? "", /auth;dur=[\d.]+, total;dur=[\d.]+/);
  assert.equal((await response.json()).code, "unauthorized");
});
