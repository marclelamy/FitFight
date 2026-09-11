import assert from "node:assert/strict";
import test from "node:test";
import { enqueueDailyStatusNotifications } from "./daily-status-supabase-query";

test("enqueueDailyStatusNotifications no-ops when OpenRouter is not configured", async () => {
  const previous = process.env.OPENROUTER_API_KEY;
  delete process.env.OPENROUTER_API_KEY;
  const result = await enqueueDailyStatusNotifications(
    new Date("2026-09-11T09:00:00.000Z"),
    Object.assign(() => { throw new Error("database should not be queried"); }, {
      begin: async () => { throw new Error("database should not be queried"); },
    }) as never,
  );
  assert.equal(result.configured, false);
  assert.equal(result.candidates, 0);
  assert.equal(result.enqueued, 0);
  if (previous) {
    process.env.OPENROUTER_API_KEY = previous;
  }
});
