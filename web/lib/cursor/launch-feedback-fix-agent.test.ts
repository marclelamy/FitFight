import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError } from "@/lib/http";
import { launchFeedbackFixAgent } from "./launch-feedback-fix-agent";
import type { FeedbackPostDetail } from "@/lib/types/feedback/feedback";
import { fitFightAgentStartingRef, fitFightGithubRepoUrl } from "@/lib/types/cursor/cloud-agent";

const detail: FeedbackPostDetail = {
  post: {
    id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
    kind: "bug",
    title: "Steps chart is blank",
    body: "The daily Steps chart on a live fight stays empty after a successful sync.",
    vote_count: 3,
    comment_count: 1,
    voted: true,
    author_handle: "maya_moves",
    created_at: "2026-09-04T12:00:00Z",
  },
  comments: [{
    id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    body: "Same here after the Watch catches up.",
    author_handle: "dorian",
    created_at: "2026-09-04T13:00:00Z",
  }],
};

function restoreEnv(name: string, previous: string | undefined) {
  if (previous === undefined) delete process.env[name];
  else process.env[name] = previous;
}

test("refuses to start an agent when CURSOR_API_KEY is missing", async () => {
  const previous = process.env.CURSOR_API_KEY;
  delete process.env.CURSOR_API_KEY;
  let called = false;
  try {
    await assert.rejects(
      () => launchFeedbackFixAgent(detail, (async () => {
        called = true;
        return new Response(null, { status: 201 });
      }) as typeof fetch),
      (error: unknown) => error instanceof ApiError && error.code === "config",
    );
    assert.equal(called, false);
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("starts a develop-branch cloud agent with the post and comments", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = "cursor_test_key";
  const calls: { url: string; headers: Headers; body: Record<string, unknown> }[] = [];
  try {
    const launched = await launchFeedbackFixAgent(detail, (async (url, init) => {
      calls.push({
        url: String(url),
        headers: new Headers(init?.headers),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      return new Response(JSON.stringify({
        agent: {
          id: "bc-00000000-0000-0000-0000-000000000001",
          url: "https://cursor.com/agents/bc-00000000-0000-0000-0000-000000000001",
        },
      }), { status: 201 });
    }) as typeof fetch);

    assert.equal(launched.agent_id, "bc-00000000-0000-0000-0000-000000000001");
    assert.equal(
      launched.agent_url,
      "https://cursor.com/agents/bc-00000000-0000-0000-0000-000000000001",
    );
    assert.equal(calls[0]?.url, "https://api.cursor.com/v1/agents");
    assert.equal(calls[0]?.headers.get("Authorization"), "Bearer cursor_test_key");
    assert.equal(calls[0]?.body.autoCreatePR, true);
    assert.equal(calls[0]?.body.skipReviewerRequest, true);
    assert.deepEqual(calls[0]?.body.repos, [{
      url: fitFightGithubRepoUrl,
      startingRef: fitFightAgentStartingRef,
    }]);
    const prompt = (calls[0]?.body.prompt as { text: string }).text;
    assert.match(prompt, /Steps chart is blank/);
    assert.match(prompt, /daily Steps chart/);
    assert.match(prompt, /@dorian/);
    assert.match(prompt, /Watch catches up/);
    assert.match(prompt, /PR into develop/);
    assert.match(prompt, /feedback_post: dddddddd-dddd-4ddd-8ddd-dddddddddddd/);
    assert.match(prompt, /Leave Status as Building/);
    assert.match(prompt, /Do not set Status to Done/);
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("maps a Cursor rate limit to a retryable API error", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = "cursor_test_key";
  try {
    await assert.rejects(
      () => launchFeedbackFixAgent(detail, (async () => {
        return new Response("slow down", { status: 429 });
      }) as typeof fetch),
      (error: unknown) => error instanceof ApiError && error.code === "rate_limited",
    );
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});
