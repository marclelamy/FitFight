import assert from "node:assert/strict";
import { test } from "node:test";
import { createAppFeedbackBacklogItem, markAppFeedbackBacklogBuilding } from "./create-app-feedback-item";
import {
  notionAppFeedbackAgentStatus,
  notionAppFeedbackDefaults,
} from "@/lib/types/notion/product-backlog";
import type { FeedbackPostSummary } from "@/lib/types/feedback/feedback";

const post: FeedbackPostSummary = {
  id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
  kind: "bug",
  title: "Steps chart is blank",
  body: "The daily Steps chart on a live fight stays empty after a successful sync.",
  vote_count: 0,
  comment_count: 0,
  voted: false,
  author_handle: "maya_moves",
  created_at: "2026-09-04T12:00:00Z",
};

function restoreEnv(name: string, previous: string | undefined) {
  if (previous === undefined) delete process.env[name];
  else process.env[name] = previous;
}

test("skips Notion when the integration token is missing", async () => {
  const previousToken = process.env.NOTION_TOKEN;
  delete process.env.NOTION_TOKEN;
  let called = false;
  try {
    const created = await createAppFeedbackBacklogItem(post, (async () => {
      called = true;
      return new Response(null, { status: 200 });
    }) as typeof fetch);
    assert.equal(created, false);
    assert.equal(called, false);
  } finally {
    restoreEnv("NOTION_TOKEN", previousToken);
  }
});

test("creates a P0 FitFight App feedback Inbox row for a bug", async () => {
  const previousToken = process.env.NOTION_TOKEN;
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NOTION_TOKEN = "ntn_test_token";
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://zstzbfocunthczzubggz.supabase.co";
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  try {
    const created = await createAppFeedbackBacklogItem(post, (async (url, init) => {
      calls.push({
        url: String(url),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      return new Response(JSON.stringify({ id: "page" }), { status: 200 });
    }) as typeof fetch);
    assert.equal(created, true);
    assert.equal(calls[0]?.url, "https://api.notion.com/v1/pages");
    const properties = calls[0]?.body.properties as {
      Name: { title: { text: { content: string } }[] };
      Notes: { rich_text: { text: { content: string } }[] };
      Priority: { select: { name: string } };
      Product: { select: { name: string } };
      Source: { select: { name: string } };
      Status: { select: { name: string } };
      Type: { select: { name: string } };
    };
    assert.equal(properties.Name.title[0]?.text.content, post.title);
    assert.match(properties.Notes.rich_text[0]?.text.content ?? "", /@maya_moves · bug · staging/);
    assert.match(properties.Notes.rich_text[0]?.text.content ?? "", /feedback_post: dddddddd-dddd-4ddd-8ddd-dddddddddddd/);
    assert.equal(properties.Priority.select.name, notionAppFeedbackDefaults.priority);
    assert.equal(properties.Product.select.name, notionAppFeedbackDefaults.product);
    assert.equal(properties.Source.select.name, notionAppFeedbackDefaults.source);
    assert.equal(properties.Status.select.name, notionAppFeedbackDefaults.status);
    assert.equal(properties.Type.select.name, "Bug");
  } finally {
    restoreEnv("NOTION_TOKEN", previousToken);
    restoreEnv("NEXT_PUBLIC_SUPABASE_URL", previousProject);
  }
});

test("maps a feature request to Type Feature and does not fail the post when Notion errors", async () => {
  const previousToken = process.env.NOTION_TOKEN;
  process.env.NOTION_TOKEN = "ntn_test_token";
  const feature = { ...post, kind: "feature" as const, title: "Show weekly totals" };
  try {
    const created = await createAppFeedbackBacklogItem(feature, (async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as {
        properties: { Type: { select: { name: string } } };
      };
      assert.equal(body.properties.Type.select.name, "Feature");
      return new Response("unavailable", { status: 503 });
    }) as typeof fetch);
    assert.equal(created, false);
  } finally {
    restoreEnv("NOTION_TOKEN", previousToken);
  }
});

test("skips moving a backlog row to Building when the token is missing", async () => {
  const previousToken = process.env.NOTION_TOKEN;
  delete process.env.NOTION_TOKEN;
  let called = false;
  try {
    const updated = await markAppFeedbackBacklogBuilding(post.id, (async () => {
      called = true;
      return new Response(null, { status: 200 });
    }) as typeof fetch);
    assert.equal(updated, false);
    assert.equal(called, false);
  } finally {
    restoreEnv("NOTION_TOKEN", previousToken);
  }
});

test("moves the matching App feedback row to Building", async () => {
  const previousToken = process.env.NOTION_TOKEN;
  process.env.NOTION_TOKEN = "ntn_test_token";
  const calls: { url: string; method: string; body: Record<string, unknown> }[] = [];
  try {
    const updated = await markAppFeedbackBacklogBuilding(post.id, (async (url, init) => {
      calls.push({
        url: String(url),
        method: String(init?.method),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      if (String(url).includes("/query")) {
        return new Response(JSON.stringify({
          results: [{ id: "11111111-1111-4111-8111-111111111111" }],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ id: "11111111-1111-4111-8111-111111111111" }), { status: 200 });
    }) as typeof fetch);
    assert.equal(updated, true);
    assert.match(calls[0]?.url ?? "", /\/v1\/databases\/.*\/query/);
    const filter = calls[0]?.body.filter as {
      property: string;
      rich_text: { contains: string };
    };
    assert.equal(filter.property, "Notes");
    assert.equal(filter.rich_text.contains, `feedback_post: ${post.id}`);
    assert.equal(
      calls[1]?.url,
      "https://api.notion.com/v1/pages/11111111-1111-4111-8111-111111111111",
    );
    assert.equal(calls[1]?.method, "PATCH");
    const properties = calls[1]?.body.properties as {
      Status: { select: { name: string } };
    };
    assert.equal(properties.Status.select.name, notionAppFeedbackAgentStatus);
  } finally {
    restoreEnv("NOTION_TOKEN", previousToken);
  }
});

test("does not patch Notion when no backlog row matches the feedback post", async () => {
  const previousToken = process.env.NOTION_TOKEN;
  process.env.NOTION_TOKEN = "ntn_test_token";
  const methods: string[] = [];
  try {
    const updated = await markAppFeedbackBacklogBuilding(post.id, (async (_url, init) => {
      methods.push(String(init?.method));
      return new Response(JSON.stringify({ results: [] }), { status: 200 });
    }) as typeof fetch);
    assert.equal(updated, false);
    assert.deepEqual(methods, ["POST"]);
  } finally {
    restoreEnv("NOTION_TOKEN", previousToken);
  }
});
