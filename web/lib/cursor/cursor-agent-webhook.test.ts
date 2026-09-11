import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";
import { ApiError } from "@/lib/http";
import { handleCursorAgentWebhook } from "./cursor-agent-webhook";
import { notionAppFeedbackDoneStatus } from "@/lib/types/notion/product-backlog";

const postId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const longCursorKey = "cursor_test_key_32_chars_minimum!";
const prUrl = "https://github.com/marclelamy/FitFight/pull/128";

function restoreEnv(name: string, previous: string | undefined) {
  if (previous === undefined) delete process.env[name];
  else process.env[name] = previous;
}

function signedRequest(body: unknown, secret = longCursorKey) {
  const rawBody = JSON.stringify(body);
  const signature = `sha256=${createHmac("sha256", secret).update(rawBody).digest("hex")}`;
  return new Request(`https://staging.fitfight.app/api/internal/cursor-agent/${postId}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-webhook-signature": signature,
    },
    body: rawBody,
  });
}

const finishedPayload = {
  event: "statusChange",
  id: "bc-00000000-0000-0000-0000-000000000001",
  status: "FINISHED",
  target: { prUrl },
};

test("rejects a webhook with a bad signature", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  try {
    await assert.rejects(
      () => handleCursorAgentWebhook(postId, new Request(
        `https://staging.fitfight.app/api/internal/cursor-agent/${postId}`,
        {
          method: "POST",
          headers: { "x-webhook-signature": "sha256=deadbeef" },
          body: JSON.stringify(finishedPayload),
        },
      )),
      (error: unknown) => error instanceof ApiError && error.code === "unauthorized",
    );
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("marks the matching backlog row Done and stores the PR URL", async () => {
  const previous = process.env.CURSOR_API_KEY;
  const previousToken = process.env.NOTION_TOKEN;
  process.env.CURSOR_API_KEY = longCursorKey;
  process.env.NOTION_TOKEN = "ntn_test_token";
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  try {
    const result = await handleCursorAgentWebhook(
      postId,
      signedRequest(finishedPayload),
      (async (url, init) => {
        calls.push({
          url: String(url),
          body: JSON.parse(String(init?.body)) as Record<string, unknown>,
        });
        if (String(url).includes("/query")) {
          return new Response(JSON.stringify({
            results: [{
              id: "11111111-1111-4111-8111-111111111111",
              properties: {
                Notes: { rich_text: [{ plain_text: `feedback_post: ${postId}` }] },
              },
            }],
          }), { status: 200 });
        }
        return new Response(JSON.stringify({ id: "11111111-1111-4111-8111-111111111111" }), { status: 200 });
      }) as typeof fetch,
    );
    assert.deepEqual(result, { ok: true, updated: true });
    const properties = calls[1]?.body.properties as {
      Status: { select: { name: string } };
      Notes: { rich_text: { text: { content: string } }[] };
    };
    assert.equal(properties.Status.select.name, notionAppFeedbackDoneStatus);
    assert.match(properties.Notes.rich_text[0]?.text.content ?? "", /feedback_post: /);
    assert.match(properties.Notes.rich_text[0]?.text.content ?? "", new RegExp(prUrl));
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
    restoreEnv("NOTION_TOKEN", previousToken);
  }
});

test("leaves Building alone when the agent errors", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  let called = false;
  try {
    const result = await handleCursorAgentWebhook(
      postId,
      signedRequest({
        event: "statusChange",
        id: "bc-00000000-0000-0000-0000-000000000001",
        status: "ERROR",
      }),
      (async () => {
        called = true;
        return new Response(null, { status: 200 });
      }) as typeof fetch,
    );
    assert.deepEqual(result, { ok: true, updated: false });
    assert.equal(called, false);
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});

test("does not mark Done when a finished run has no PR", async () => {
  const previous = process.env.CURSOR_API_KEY;
  process.env.CURSOR_API_KEY = longCursorKey;
  let called = false;
  try {
    const result = await handleCursorAgentWebhook(
      postId,
      signedRequest({
        event: "statusChange",
        id: "bc-00000000-0000-0000-0000-000000000001",
        status: "FINISHED",
      }),
      (async () => {
        called = true;
        return new Response(null, { status: 200 });
      }) as typeof fetch,
    );
    assert.deepEqual(result, { ok: true, updated: false });
    assert.equal(called, false);
  } finally {
    restoreEnv("CURSOR_API_KEY", previous);
  }
});
