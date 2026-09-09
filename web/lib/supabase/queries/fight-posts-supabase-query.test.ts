import assert from "node:assert/strict";
import { test } from "node:test";
import { GET as listFeed } from "@/app/api/v1/feed/route";
import { POST as blockAuthor } from "@/app/api/v1/feed/blocks/route";
import { GET as listPosts, POST as createPost } from "@/app/api/v1/fights/[fightID]/posts/route";
import { DELETE as deletePost } from "@/app/api/v1/fights/[fightID]/posts/[postID]/route";
import { POST as reportPost } from "@/app/api/v1/fights/[fightID]/posts/[postID]/report/route";
import {
  createFightPostRequestSchema,
  listFightPostsQuerySchema,
  reportFightPostRequestSchema,
} from "@/lib/types/feed/fight-post";
import { listFightPosts } from "./fight-posts-supabase-query";
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
});

test("listing fight posts requires roster membership before reading rows", async () => {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    if (sql.includes("from public.fight_members")) return Promise.resolve([]);
    return Promise.resolve([]);
  }) as unknown as Sql;
  await assert.rejects(listFightPosts(userId, fightId, { limit: 30 }, query), (error: unknown) => (
    error instanceof Error && error.message === "Join this fight to see its posts"
  ));
  assert.match(queries[0] ?? "", /from public.fight_members/);
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
  for (const response of [feed, posts, created, removed, reported, blocked]) {
    assert.equal(response.status, 401);
  }
});
