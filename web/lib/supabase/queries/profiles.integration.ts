import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { ApiError } from "@/lib/http";
import { updateProfileRequestSchema } from "@/lib/types/profiles/profile";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { deleteAccount } from "./delete-account-supabase-query";
import { readProfile, updateProfile } from "./profiles-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
after(() => database.end());

test("Auth, profile commands, and deletion work before and after direct client access closes", async (t) => {
  const email = `profile-${randomUUID()}@example.com`;
  const password = randomUUID();
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  assert.equal(created.error, null);
  assert.ok(created.data.user);
  const userId = created.data.user.id;
  const peerId = randomUUID();
  t.after(async () => {
    await database`delete from auth.users where id in (${userId}, ${peerId})`;
  });
  await database`insert into auth.users (id) values (${peerId})`;

  const client = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const signedIn = await client.auth.signInWithPassword({ email, password });
  assert.equal(signedIn.error, null);
  assert.ok(signedIn.data.session);
  const verified = await admin.auth.getUser(signedIn.data.session.access_token);
  assert.equal(verified.error, null);
  assert.equal(verified.data.user?.id, userId);

  const initial = await readProfile(userId, admin);
  assert.equal(initial.handle_set_at, null);
  const named = await updateProfile(userId, { display_name: "Apple Name" }, admin);
  assert.equal(named.handle, initial.handle);
  assert.equal(named.handle_set_at, null);
  const handle = `ci_${randomUUID().replaceAll("-", "").slice(0, 20)}`;
  const before = Date.now();
  const updated = await updateProfile(userId, updateProfileRequestSchema.parse({ handle: ` @${handle.toUpperCase()} ` }), admin);
  assert.equal(updated.handle, handle);
  assert.equal(updated.display_name, "Apple Name");
  assert.equal(updated.referral_code, initial.referral_code);
  assert.ok(updated.handle_set_at && Date.parse(updated.handle_set_at) >= before);
  await assert.rejects(updateProfile(peerId, { handle }, admin),
    (error: unknown) => error instanceof ApiError && error.code === "handle_taken");

  const directRead = await client.from("profiles").select("user_id").eq("user_id", userId);
  const directWrite = await client.from("profiles").update({ display_name: "Direct Name" }).eq("user_id", userId);
  if (env.SUPABASE_CLIENT_ACCESS_CLOSED) {
    assert.equal(directRead.error?.code, "42501");
    assert.equal(directWrite.error?.code, "42501");
    assert.equal((await readProfile(userId, admin)).display_name, "Apple Name");
  } else {
    assert.equal(directRead.error, null);
    assert.deepEqual(directRead.data, [{ user_id: userId }]);
    assert.equal(directWrite.error, null);
    assert.equal((await readProfile(userId, admin)).display_name, "Direct Name");
  }
  const anonymous = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  assert.equal((await anonymous.from("profiles").select("user_id")).error?.code, "42501");

  await database`update public.profiles set deleted_at = now() where user_id = ${peerId}`;
  await assert.rejects(readProfile(peerId, admin),
    (error: unknown) => error instanceof ApiError && error.code === "profile_missing");
  await assert.rejects(updateProfile(peerId, { display_name: "Gone" }, admin),
    (error: unknown) => error instanceof ApiError && error.code === "profile_missing");
  assert.equal(await deleteAccount(userId, database), false);
  await assert.rejects(readProfile(userId, admin),
    (error: unknown) => error instanceof ApiError && error.code === "profile_missing");
  const [remaining] = await database`select count(*)::integer as count from auth.users where id = ${userId}`;
  assert.equal(remaining.count, 0);
});
