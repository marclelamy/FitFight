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
const agentId = "bc-00000000-0000-0000-0000-000000000001";
const agentUrl = `https://cursor.com/agents/${agentId}`;

function restoreEnv(name: string, previous: string | undefined) {
  if (previous === undefined) delete process.env[name];
  else process.env[name] = previous;
}

function v1CreatedResponse(url?: string) {
  return new Response(JSON.stringify({
    agent: {
      id: agentId,
      ...(url === undefined ? {} : { url }),
    },
    run: {
      id: "run-00000000-0000-0000-0000-000000000001",
      status: "CREATING",
    },
  }), { status: 201 });
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

test("starts a v1 cloud agent on develop without a webhook", async () => {
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
      return v1CreatedResponse(agentUrl);
    }) as typeof fetch);

    assert.equal(launched.agent_id, agentId);
    assert.equal(launched.agent_url, agentUrl);
    assert.equal(calls[0]?.url, "https://api.cursor.com/v1/agents");
    assert.equal(
      calls[0]?.headers.get("Authorization"),
      `Basic ${Buffer.from(`${longCursorKey}:`, "utf8").toString("base64")}`,
    );
    assert.equal(calls[0]?.body.source, undefined);
    assert.equal(calls[0]?.body.webhook, undefined);
    assert.equal(calls[0]?.body.target, undefined);
    assert.deepEqual(calls[0]?.body.repos, [{
      url: fitFightGithubRepoUrl,
      startingRef: fitFightAgentStartingRef,
    }]);
    assert.equal(calls[0]?.body.autoCreatePR, true);
    assert.equal(calls[0]?.body.skipReviewerRequest, true);
    assert.equal(calls[0]?.body.name, "Steps chart is blank");
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

test("builds the agent URL when Cursor omits it", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  try {
    const launched = await launchFeedbackFixAgent(detail, (async () => {
      return v1CreatedResponse();
    }) as typeof fetch);
    assert.equal(launched.agent_id, agentId);
    assert.equal(launched.agent_url, agentUrl);
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("maps an unrecognized Cursor 502 to the short client message and stores the upstream body", async () => {
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

test("maps a rejected API key to a useful 502, not a session 401", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  try {
    await assert.rejects(
      () => launchFeedbackFixAgent(detail, (async () => {
        return new Response(JSON.stringify({
          code: "error",
          message: "Invalid User API Key",
        }), { status: 401 });
      }) as typeof fetch),
      (error: unknown) => (
        error instanceof ApiError
        && error.status === 502
        && error.code === "internal"
        && error.message === "Cursor rejected the API key on Vercel Preview."
      ),
    );
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("maps a GitHub access error to a useful 502", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  try {
    await assert.rejects(
      () => launchFeedbackFixAgent(detail, (async () => {
        return new Response(JSON.stringify({
          error: {
            code: "repository_access",
            message: "The API key cannot access this repository",
          },
        }), { status: 400 });
      }) as typeof fetch),
      (error: unknown) => (
        error instanceof ApiError
        && error.status === 502
        && error.message === "Cursor can’t access the FitFight GitHub repo with this API key."
      ),
    );
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("maps a Cursor timeout to a useful 504", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  try {
    await assert.rejects(
      () => launchFeedbackFixAgent(detail, (async () => {
        const error = new Error("The operation was aborted due to timeout");
        error.name = "TimeoutError";
        throw error;
      }) as typeof fetch),
      (error: unknown) => (
        error instanceof ApiError
        && error.status === 504
        && error.message === "Cursor took too long to start. Try again."
      ),
    );
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});
