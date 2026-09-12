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
    author_id: "22222222-2222-4222-8222-222222222222",
    author_handle: "maya_moves",
    mine: false,
    created_at: "2026-09-04T12:00:00Z",
    metadata: { app_version: "1.0.0", os: "iOS", os_version: "26.0" },
  },
  comments: [{
    id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    body: "Same here after the Watch catches up.",
    author_handle: "dorian",
    created_at: "2026-09-04T13:00:00Z",
    metadata: { app_build: "183", language: "fr" },
  }],
};

const longCursorKey = "cursor_test_key_32_chars_minimum!";
const requestUrl = "https://staging.fitfight.app/api/v1/feedback/dddddddd-dddd-4ddd-8ddd-dddddddddddd/fix-agent";

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

test("starts a develop-branch cloud agent with the post, comments, and a Done webhook", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  const calls: { url: string; headers: Headers; body: Record<string, unknown> }[] = [];
  try {
    const launched = await launchFeedbackFixAgent(detail, (async (url, init) => {
      calls.push({
        url: String(url),
        headers: new Headers(init?.headers),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      return new Response(JSON.stringify({
        id: "bc-00000000-0000-0000-0000-000000000001",
        target: {
          url: "https://cursor.com/agents?id=bc-00000000-0000-0000-0000-000000000001",
        },
      }), { status: 201 });
    }) as typeof fetch, requestUrl);

    assert.equal(launched.agent_id, "bc-00000000-0000-0000-0000-000000000001");
    assert.equal(
      launched.agent_url,
      "https://cursor.com/agents?id=bc-00000000-0000-0000-0000-000000000001",
    );
    assert.equal(calls[0]?.url, "https://api.cursor.com/v0/agents");
    assert.equal(
      calls[0]?.headers.get("Authorization"),
      `Basic ${Buffer.from(`${longCursorKey}:`, "utf8").toString("base64")}`,
    );
    assert.deepEqual(calls[0]?.body.source, {
      repository: fitFightGithubRepoUrl,
      ref: fitFightAgentStartingRef,
    });
    assert.deepEqual(calls[0]?.body.target, {
      autoCreatePr: true,
      skipReviewerRequest: true,
    });
    assert.deepEqual(calls[0]?.body.webhook, {
      url: "https://staging.fitfight.app/api/internal/cursor-agent/dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      secret: longCursorKey,
    });
    const prompt = (calls[0]?.body.prompt as { text: string }).text;
    assert.match(prompt, /Steps chart is blank/);
    assert.match(prompt, /daily Steps chart/);
    assert.match(prompt, /@dorian/);
    assert.match(prompt, /Watch catches up/);
    assert.match(prompt, /PR into develop/);
    assert.match(prompt, /Feedback post ID: dddddddd-dddd-4ddd-8ddd-dddddddddddd/);
    assert.match(prompt, /Device: .*iOS/);
    assert.match(prompt, /Do not create or update Notion rows/);
    assert.match(prompt, /https:\/\/github.com\/slooowshutter\/FitFight/);
    assert.equal(fitFightGithubRepoUrl, "https://github.com/slooowshutter/FitFight");
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("omits the webhook when the API key is too short to sign it", async () => {
  const previous = process.env.CURSOR_API_KEY;
  const previousCron = process.env.CRON_SECRET;
  process.env.CURSOR_API_KEY = "cursor_test_key";
  delete process.env.CRON_SECRET;
  try {
    const launched = await launchFeedbackFixAgent(detail, (async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
      assert.equal(body.webhook, undefined);
      return new Response(JSON.stringify({
        id: "bc-00000000-0000-0000-0000-000000000001",
        target: { url: "https://cursor.com/agents?id=bc-00000000-0000-0000-0000-000000000001" },
      }), { status: 201 });
    }) as typeof fetch, requestUrl);
    assert.equal(launched.agent_id, "bc-00000000-0000-0000-0000-000000000001");
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
    restoreEnv("CRON_SECRET", previousCron);
  }
});

test("maps a Cursor failure to 502 without changing the client message", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  try {
    await assert.rejects(
      () => launchFeedbackFixAgent(detail, (async () => {
        return new Response(JSON.stringify({ message: "cloud agents unavailable" }), { status: 502 });
      }) as typeof fetch),
      (error: unknown) => (
        error instanceof ApiError
        && error.status === 502
        && error.code === "internal"
        && error.message === "Could not start the Cursor agent."
        && JSON.stringify(error.detail).includes("cloud agents unavailable")
      ),
    );
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("maps a Cursor rate limit to a retryable API error", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
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
