import assert from "node:assert/strict";
import test from "node:test";
import { isOpenRouterConfigured } from "./generate-daily-status";

test("isOpenRouterConfigured is false when the key is missing", () => {
  const previous = process.env.OPENROUTER_API_KEY;
  delete process.env.OPENROUTER_API_KEY;
  assert.equal(isOpenRouterConfigured(), false);
  if (previous) {
    process.env.OPENROUTER_API_KEY = previous;
  }
});

test("isOpenRouterConfigured is true when the key is set", () => {
  process.env.OPENROUTER_API_KEY = "test-key";
  assert.equal(isOpenRouterConfigured(), true);
  delete process.env.OPENROUTER_API_KEY;
});
