import assert from "node:assert/strict";
import { test } from "node:test";
import { GET as listFeed } from "@/app/api/v1/feed/route";
import { POST as blockAuthor } from "@/app/api/v1/feed/blocks/route";
import { GET as listPeople } from "@/app/api/v1/feed/people/route";
import { POST as createFeedPosts } from "@/app/api/v1/feed/posts/route";
import { GET as listPosts, POST as createPost } from "@/app/api/v1/fights/[fightID]/posts/route";
import { DELETE as deletePost } from "@/app/api/v1/fights/[fightID]/posts/[postID]/route";
import { POST as reportPost } from "@/app/api/v1/fights/[fightID]/posts/[postID]/report/route";
import { GET as listComments, POST as createComment } from "@/app/api/v1/posts/[postID]/comments/route";
import { PATCH as updatePost } from "@/app/api/v1/posts/[postID]/route";
import { POST as reactToPost } from "@/app/api/v1/posts/[postID]/reactions/route";
import {
  createFeedPostsRequestSchema,
  createFightPostCommentRequestSchema,
  createFightPostRequestSchema,
  listFightPostsQuerySchema,
  reportFightPostRequestSchema,
  setFightPostReactionRequestSchema,
  updateFightPostRequestSchema,
} from "@/lib/types/feed/fight-post";
import { listFeedPeople, listFightPosts } from "./fight-posts-supabase-query";
import type { Sql } from "postgres";

const userId = "11111111-1111-4111-8111-111111111111";
const fightId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const postId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

test("fight posts need a note or a photo and reject extra fields", () => {
  assert.deepEqual(createFightPostRequestSchema.parse({ body: "Made it up the hill." }), {
    body: "Made it up the hill.",
    media_ids: [],
  });
  assert.equal(createFightPostRequestSchema.safeParse({}).success, false);
  assert.equal(createFightPostRequestSchema.safeParse({ body: "", media_ids: [] }).success, false);
  assert.equal(createFightPostRequestSchema.safeParse({
    body: "x",
    media_ids: ["not-a-uuid"],
  }).success, false);
  assert.equal(createFightPostRequestSchema.safeParse({
    body: "x",
    fight_id: fightId,
  }).success, false);
  assert.equal(reportFightPostRequestSchema.safeParse({ reason: "nope" }).success, false);
  assert.deepEqual(listFightPostsQuerySchema.parse({}), { limit: 30 });
  assert.deepEqual(listFightPostsQuerySchema.parse({ scope: "all" }), { limit: 30, scope: "all" });
  assert.deepEqual(createFeedPostsRequestSchema.parse({
    body: "Hill.",
    destinations: [{ type: "main" }, { type: "fight", fight_id: fightId }],
  }), {
    body: "Hill.",
    media_ids: [],
    destinations: [{ type: "main" }, { type: "fight", fight_id: fightId }],
    tagged_user_ids: [],
  });
  assert.equal(createFeedPostsRequestSchema.safeParse({
    body: "Hill.",
    destinations: Array.from({ length: 9 }, () => ({ type: "fight" as const, fight_id: fightId })),
  }).success, true);
  assert.equal(createFeedPostsRequestSchema.safeParse({
    body: "Hill.",
    destinations: [],
  }).success, false);
  assert.equal(createFightPostCommentRequestSchema.safeParse({ body: "" }).success, false);
  assert.equal(setFightPostReactionRequestSchema.safeParse({ emoji: "abc" }).success, false);
  assert.equal(setFightPostReactionRequestSchema.safeParse({ emoji: "🔥" }).success, true);
  assert.deepEqual(updateFightPostRequestSchema.parse({ body: "  edited  " }), { body: "edited" });
  assert.equal(updateFightPostRequestSchema.safeParse({ body: "x".repeat(501) }).success, false);
  assert.equal(updateFightPostRequestSchema.safeParse({ body: "", media_ids: [] }).success, false);
});

test("listing fight posts requires roster membership before reading rows", async () => {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    if (sql.includes("from public.fight_members") && !sql.includes("fight_posts")) {
      return Promise.resolve([]);
    }
    return Promise.resolve([]);
  }) as unknown as Sql;
  await assert.rejects(listFightPosts(userId, fightId, { limit: 30 }, query), (error: unknown) => (
    error instanceof Error && error.message === "Join this fight to see its posts"
  ));
  assert.match(queries[0] ?? "", /from public.fight_members/);
});

test("main feed listing skips the fight roster gate", async () => {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    return Promise.resolve([]);
  }) as unknown as Sql;
  const result = await listFightPosts(userId, undefined, { limit: 30, scope: "main" }, query);
  assert.deepEqual(result, { posts: [], next_cursor: null });
  assert.equal(queries.some((sql) => sql.includes("from public.fight_members") && !sql.includes("fight_posts")), false);
  assert.match(queries[0] ?? "", /audience = 'main'/);
});

test("one feed listing includes main and fight posts", async () => {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    return Promise.resolve([]);
  }) as unknown as Sql;
  const result = await listFightPosts(userId, undefined, { limit: 30, scope: "all" }, query);
  assert.deepEqual(result, { posts: [], next_cursor: null });
  assert.equal(queries.some((sql) => sql.includes("from public.fight_members") && !sql.includes("fight_posts")), false);
  assert.match(queries[0] ?? "", /audience = 'main'/);
  assert.match(queries[0] ?? "", /audience = 'fight'/);
});

test("fight post listing keeps posts from other windows in the same series", async () => {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    if (sql.includes("from public.fight_members") && !sql.includes("fight_posts")) {
      return Promise.resolve([{ state: "accepted" }]);
    }
    return Promise.resolve([]);
  }) as unknown as Sql;
  const result = await listFightPosts(userId, fightId, { limit: 30 }, query);
  assert.deepEqual(result, { posts: [], next_cursor: null });
  assert.match(queries[1] ?? "", /series_id/);
  assert.match(queries[1] ?? "", /sibling/);
});

test("feed people listing only includes opponents from finished fights", async () => {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    return Promise.resolve([]);
  }) as unknown as Sql;
  const result = await listFeedPeople(userId, { main: "true" }, query);
  assert.deepEqual(result, { people: [] });
  assert.ok(queries.some((sql) => /done_fight.state = 'final'/.test(sql)));
});

test("feed and fight post routes authenticate before reading or writing", async () => {
  const context = { params: Promise.resolve({ fightID: fightId, postID: postId }) };
  const feed = await listFeed(new Request("https://staging.fitfight.app/api/v1/feed"), {
    params: Promise.resolve({}),
  });
  const posts = await listPosts(new Request(`https://staging.fitfight.app/api/v1/fights/${fightId}/posts`), context);
  const created = await createPost(new Request(`https://staging.fitfight.app/api/v1/fights/${fightId}/posts`, {
    method: "POST",
  }), context);
  const removed = await deletePost(new Request(`https://staging.fitfight.app/api/v1/fights/${fightId}/posts/${postId}`, {
    method: "DELETE",
  }), context);
  const reported = await reportPost(new Request(`https://staging.fitfight.app/api/v1/fights/${fightId}/posts/${postId}/report`, {
    method: "POST",
  }), context);
  const blocked = await blockAuthor(new Request("https://staging.fitfight.app/api/v1/feed/blocks", {
    method: "POST",
  }), { params: Promise.resolve({}) });
  const composed = await createFeedPosts(new Request("https://staging.fitfight.app/api/v1/feed/posts", {
    method: "POST",
  }), { params: Promise.resolve({}) });
  const people = await listPeople(new Request("https://staging.fitfight.app/api/v1/feed/people"), {
    params: Promise.resolve({}),
  });
  const updated = await updatePost(new Request(`https://staging.fitfight.app/api/v1/posts/${postId}`, {
    method: "PATCH",
  }), { params: Promise.resolve({ postID: postId }) });
  const comments = await listComments(new Request(`https://staging.fitfight.app/api/v1/posts/${postId}/comments`), {
    params: Promise.resolve({ postID: postId }),
  });
  const commented = await createComment(new Request(`https://staging.fitfight.app/api/v1/posts/${postId}/comments`, {
    method: "POST",
  }), { params: Promise.resolve({ postID: postId }) });
  const reacted = await reactToPost(new Request(`https://staging.fitfight.app/api/v1/posts/${postId}/reactions`, {
    method: "POST",
  }), { params: Promise.resolve({ postID: postId }) });
  for (const response of [feed, posts, created, removed, reported, blocked, composed, people, updated, comments, commented, reacted]) {
    assert.equal(response.status, 401);
  }
});
