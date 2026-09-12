import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import {
  blockFeedbackAuthorRequestSchema,
  createFeedbackCommentRequestSchema,
  createFeedbackPostRequestSchema,
  feedbackDetailResponseSchema,
  feedbackListResponseSchema,
  listFeedbackQuerySchema,
  reportFeedbackPostRequestSchema,
} from "@/lib/types/feedback/feedback";
import {
  blockFeedbackAuthor,
  createFeedbackComment,
  createFeedbackPost,
  listFeedbackPosts,
  reportFeedbackPost,
  toggleFeedbackVote,
} from "./feedback-supabase-query";

const userId = "11111111-1111-4111-8111-111111111111";
const authorId = "22222222-2222-4222-8222-222222222222";
const postId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

const postRow = {
  id: postId,
  kind: "bug" as const,
  title: "Steps chart is blank",
  body: "The daily Steps chart on a live fight stays empty after a successful sync.",
  vote_count: 3,
  comment_count: 1,
  voted: true,
  author_id: authorId,
  author_handle: "maya_moves",
  mine: false,
  created_at: new Date("2026-09-04T12:00:00.000Z"),
  metadata: {
    app_version: "1.0.0",
    app_build: "183",
    os: "iOS",
    os_version: "26.0",
    language: "fr",
  },
};

function createDatabaseStub(respond: (query: string) => unknown[]) {
  const queries: string[] = [];
  const bound: unknown[][] = [];
  const query = ((first: TemplateStringsArray, ...values: unknown[]) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    bound.push(values);
    return Promise.resolve(respond(sql));
  }) as unknown as Sql;
  const database = Object.assign(query, {
    begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) => callback(query),
    json: (value: unknown) => value,
  });
  return { database, queries, bound };
}

test("feedback schemas accept a one-character title and details", () => {
  const created = createFeedbackPostRequestSchema.parse({
    kind: "feature",
    title: "H",
    body: "A",
  });
  assert.equal(created.kind, "feature");
  assert.equal(created.title, "H");
  assert.equal(created.body, "A");
  assert.throws(() => createFeedbackPostRequestSchema.parse({
    kind: "feature",
    title: " ",
    body: "A weekly Steps total on You would make it easier to plan a fight.",
  }));
  assert.throws(() => createFeedbackPostRequestSchema.parse({
    kind: "feature",
    title: "Show weekly totals",
    body: " ",
  }));
  assert.throws(() => createFeedbackPostRequestSchema.parse({
    kind: "idea",
    title: "Show weekly totals",
    body: "A weekly Steps total on You would make it easier to plan a fight.",
  }));
  assert.throws(() => createFeedbackCommentRequestSchema.parse({ body: "x" }));
  assert.deepEqual(
    createFeedbackPostRequestSchema.parse({
      kind: "bug",
      title: "H",
      body: "A",
      metadata: {
        app_version: "1.0.0",
        app_build: "183",
        language: "fr",
        os: "iOS",
        os_version: "26.0",
        extra_flag: true,
      },
    }).metadata,
    {
      app_version: "1.0.0",
      app_build: "183",
      language: "fr",
      os: "iOS",
      os_version: "26.0",
      extra_flag: true,
    },
  );
  assert.throws(() => createFeedbackPostRequestSchema.parse({
    kind: "bug",
    title: "H",
    body: "A",
    metadata: { app_version: "x".repeat(9000) },
  }));
  assert.deepEqual(listFeedbackQuerySchema.parse({}), {});
  assert.deepEqual(listFeedbackQuerySchema.parse({}), {});
  assert.equal(listFeedbackQuerySchema.parse({ kind: "bug" }).kind, "bug");
  assert.equal(feedbackDetailResponseSchema.parse({
    post: {
      id: postId,
      kind: "bug",
      title: postRow.title,
      body: postRow.body,
      vote_count: 3,
      comment_count: 1,
      voted: true,
      author_id: authorId,
      author_handle: "maya_moves",
      mine: false,
      created_at: "2026-09-04T12:00:00Z",
      metadata: postRow.metadata,
    },
    comments: [],
    can_launch_fix: true,
  }).can_launch_fix, true);
  assert.equal(reportFeedbackPostRequestSchema.safeParse({ reason: "other" }).success, true);
  assert.equal(blockFeedbackAuthorRequestSchema.safeParse({ user_id: authorId }).success, true);
});

test("listing feedback posts maps vote counts and the viewer vote", async () => {
  const { database, queries } = createDatabaseStub(() => [postRow]);

  const result = await listFeedbackPosts(userId, { kind: "bug" }, database);

  assert.match(queries[0] ?? "", /from public.feedback_posts as post/);
  assert.match(queries[0] ?? "", /private.feedback_blocks/);
  assert.deepEqual(feedbackListResponseSchema.parse(result), {
    posts: [{
      id: postId,
      kind: "bug",
      title: postRow.title,
      body: postRow.body,
      vote_count: 3,
      comment_count: 1,
      voted: true,
      author_id: authorId,
      author_handle: "maya_moves",
      mine: false,
      created_at: "2026-09-04T12:00:00Z",
      metadata: postRow.metadata,
    }],
  });
});

test("creating a feedback post is refused after the daily cap", async () => {
  const { database, queries } = createDatabaseStub((sql) => {
    if (sql.includes("interval '24 hours'")) {
      return [{ n: 8 }];
    }
    return [postRow];
  });

  await assert.rejects(
    () => createFeedbackPost(userId, {
      kind: "bug",
      title: postRow.title,
      body: postRow.body,
    }, database),
    (error: unknown) => error instanceof ApiError && error.code === "rate_limited",
  );
  assert.equal(queries.some((query) => query.includes("insert into public.feedback_posts")), false);
});

test("creating a feedback post inserts the trimmed write-up", async () => {
  const { database, queries, bound } = createDatabaseStub((sql) => {
    if (sql.includes("interval '24 hours'")) {
      return [{ n: 1 }];
    }
    return [{ ...postRow, vote_count: 0, comment_count: 0, voted: false }];
  });

  const result = await createFeedbackPost(userId, {
    kind: "bug",
    title: postRow.title,
    body: postRow.body,
    metadata: {
      app_version: "1.0.0",
      os: "iOS",
    },
  }, database);

  assert.ok(queries.some((query) => query.includes("insert into public.feedback_posts")));
  assert.ok(queries.some((query) => query.includes("metadata")));
  assert.deepEqual(
    bound.flat().find((value) => (
      typeof value === "object"
      && value !== null
      && "app_version" in value
    )),
    { app_version: "1.0.0", os: "iOS" },
  );
  assert.equal(
    bound.flat().some((value) => typeof value === "string" && value.startsWith("{")),
    false,
  );
  assert.equal(result.post.vote_count, 0);
  assert.equal(result.post.voted, false);
  assert.equal(result.post.author_handle, "maya_moves");
  assert.deepEqual(result.post.metadata, postRow.metadata);
});

test("toggling a vote inserts when the viewer has not voted", async () => {
  const { database, queries } = createDatabaseStub((sql) => {
    if (sql.includes("select id from public.feedback_posts")) {
      return [{ id: postId }];
    }
    if (sql.includes("delete from public.feedback_votes")) {
      return [];
    }
    if (sql.includes("insert into public.feedback_votes")) {
      return [];
    }
    return [{ vote_count: 1 }];
  });

  const result = await toggleFeedbackVote(userId, postId, database);

  assert.equal(result.voted, true);
  assert.equal(result.vote_count, 1);
  assert.ok(queries.some((query) => query.includes("insert into public.feedback_votes")));
  assert.ok(queries.some((query) => query.includes("on conflict (post_id, user_id) do nothing")));
});

test("reporting a feedback post records the reason", async () => {
  const { database, queries } = createDatabaseStub((sql) => {
    if (sql.includes("from public.feedback_posts as post")) {
      return [{ id: postId, author_id: authorId }];
    }
    return [];
  });

  const result = await reportFeedbackPost(userId, postId, { reason: "other" }, database);

  assert.deepEqual(result, { reported: true });
  assert.ok(queries.some((query) => query.includes("insert into private.feedback_post_reports")));
});

test("blocking a feedback author hides them from the viewer", async () => {
  const { database, queries } = createDatabaseStub((sql) => {
    if (sql.includes("select user_id from public.profiles")) {
      return [{ user_id: authorId }];
    }
    return [];
  });

  const result = await blockFeedbackAuthor(userId, authorId, database);

  assert.deepEqual(result, { blocked: true });
  assert.ok(queries.some((query) => query.includes("insert into private.feedback_blocks")));
});

test("commenting on a missing post returns not found", async () => {
  const { database } = createDatabaseStub((sql) => {
    if (sql.includes("interval '24 hours'")) {
      return [{ n: 0 }];
    }
    return [];
  });

  await assert.rejects(
    () => createFeedbackComment(userId, postId, { body: "I see this too." }, database),
    (error: unknown) => error instanceof ApiError && error.code === "not_found",
  );
});

test("creating a feedback comment stores client metadata", async () => {
  const { database, queries, bound } = createDatabaseStub((sql) => {
    if (sql.includes("interval '24 hours'")) {
      return [{ n: 0 }];
    }
    return [{
      id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      body: "I see this too.",
      author_handle: "maya_moves",
      created_at: new Date("2026-09-04T13:00:00.000Z"),
      metadata: { app_version: "1.0.0", os: "iOS" },
    }];
  });

  const result = await createFeedbackComment(userId, postId, {
    body: "I see this too.",
    metadata: { app_version: "1.0.0", os: "iOS" },
  }, database);

  assert.ok(queries.some((query) => query.includes("insert into public.feedback_comments")));
  assert.ok(queries.some((query) => query.includes("metadata")));
  assert.deepEqual(
    bound.flat().find((value) => (
      typeof value === "object"
      && value !== null
      && "app_version" in value
    )),
    { app_version: "1.0.0", os: "iOS" },
  );
  assert.equal(
    bound.flat().some((value) => typeof value === "string" && value.startsWith("{")),
    false,
  );
  assert.deepEqual(result.comment.metadata, { app_version: "1.0.0", os: "iOS" });
});
