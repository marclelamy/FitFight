import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { deleteAccount } from "./delete-account-supabase-query";

process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY = "test-secret-key";

function createDatabaseStub(options: {
  profileExists: boolean;
}) {
  const queries: string[] = [];
  const query = ((first: TemplateStringsArray, ..._values: unknown[]) => {
    const sql = first.join("?").replace(/\s+/g, " ").trim();
    queries.push(sql);
    if (sql.includes("select user_id from public.profiles")) {
      return Promise.resolve(options.profileExists ? [{ user_id: "user-id" }] : []);
    }
    return Promise.resolve([]);
  }) as unknown as Sql;
  Object.assign(query, {
    array: (values: readonly unknown[]) => values,
  });
  const database = Object.assign(query, {
    begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) => callback(query),
  });
  return { database, queries };
}

test("account deletion removes owned Fights and every user-owned row before the auth user", async () => {
  const { database, queries } = createDatabaseStub({ profileExists: true });

  const appleAuthorizationRevoked = await deleteAccount("user-id", database);

  assert.equal(appleAuthorizationRevoked, false);
  for (const table of [
    "public.feedback_votes",
    "public.feedback_comments",
    "public.feedback_posts",
    "private.fight_post_reports",
    "private.feed_blocks",
    "public.fight_posts",
    "public.media_objects",
    "public.fights",
    "public.fight_series",
    "public.fight_series_members",
    "private.fight_score_snapshots",
    "private.metric_observations",
    "private.provider_events",
    "private.provider_uploads",
    "private.healthkit_step_source_days",
    "private.healthkit_step_sample_deletions",
    "private.healthkit_step_samples",
    "private.healthkit_step_syncs",
    "public.metric_days",
    "public.step_days",
    "public.fight_members",
    "public.fight_invites",
    "public.friendships",
    "public.data_sources",
    "private.fight_join_attempts",
    "auth.sessions",
    "auth.refresh_tokens",
    "auth.identities",
    "auth.users",
  ]) {
    assert.ok(queries.some((query) => query.includes(`delete from ${table}`)), table);
  }
  assert.ok(queries.some((query) => query.includes("update public.fight_series")));
  assert.ok(queries.some((query) => query.includes("public.fights where owner_id = ?")));
  assert.ok(queries.some((query) => query.includes("public.fight_members where user_id = ?")));
  assert.equal(queries.some((query) => query.includes("update public.profiles")), false);
  assert.equal(queries.some((query) => query.includes("update auth.users")), false);
  assert.equal(queries.at(-1), "delete from auth.users where id = ?");
});

test("account deletion stops before destructive SQL when the profile is missing", async () => {
  const { database, queries } = createDatabaseStub({ profileExists: false });

  await assert.rejects(deleteAccount("user-id", database), /Account not found/);

  assert.equal(queries.some((query) => query.startsWith("delete from public.fights")), false);
  assert.equal(queries.some((query) => query.startsWith("delete from auth.users")), false);
});
