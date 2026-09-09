import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import { ApiError } from "@/lib/http";
import { profileSchema, updateProfileRequestSchema } from "@/lib/types/profiles/profile";
import { readProfile, updateProfile } from "./profiles-supabase-query";

const profile = profileSchema.parse(JSON.parse(readFileSync(
  new URL("../../../../contracts/fixtures/profile.json", import.meta.url), "utf8",
)));

test("profile patches normalize handles and reject caller-owned IDs, timestamps, and empty updates", () => {
  assert.deepEqual(updateProfileRequestSchema.parse({ handle: " @Marc_New@ " }), { handle: "marc_new" });
  assert.deepEqual(updateProfileRequestSchema.parse({ display_name: " Marc " }), { display_name: "Marc" });
  for (const input of [
    {}, { handle: "x" }, { handle: "bad-name" }, { handle: "x".repeat(31) }, { handle: null },
    { display_name: " " }, { display_name: null },
    { handle: "marc", user_id: profile.user_id },
    { handle: "marc", handle_set_at: profile.handle_set_at },
    { display_name: "Marc", referral_code: profile.referral_code },
  ]) {
    assert.equal(updateProfileRequestSchema.safeParse(input).success, false);
  }
});

test("profile reads filter by the authenticated owner and expose only the API fields", async () => {
  const admin = createClient("https://profiles.example", "test-only-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      assert.equal(request.method, "GET");
      assert.equal(url.searchParams.get("user_id"), `eq.${profile.user_id}`);
      assert.equal(url.searchParams.get("deleted_at"), "is.null");
      assert.equal(url.searchParams.get("select"), "user_id,handle,display_name,handle_set_at,referral_code,avatar_media_id");
      return Response.json([{ ...profile, deleted_at: null, internal_column: "private" }]);
    } },
  });
  assert.deepEqual(await readProfile(profile.user_id, admin), profile);
});

test("profile updates supply the handle timestamp and leave omitted fields untouched", async () => {
  const before = Date.now();
  const admin = createClient("https://profiles.example", "test-only-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      assert.equal(request.method, "PATCH");
      assert.equal(url.searchParams.get("user_id"), `eq.${profile.user_id}`);
      assert.equal(url.searchParams.get("deleted_at"), "is.null");
      const body = profileSchema.pick({ handle: true, handle_set_at: true }).strict().parse(await request.json());
      const updated = { ...profile, ...body };
      assert.ok(updated.handle_set_at && Date.parse(updated.handle_set_at) >= before);
      assert.ok(Date.parse(updated.handle_set_at) <= Date.now());
      return Response.json(updated);
    } },
  });
  const updated = await updateProfile(profile.user_id, { handle: "marc_new" }, admin);
  assert.equal(updated.handle, "marc_new");
  assert.equal(updated.display_name, profile.display_name);
  assert.equal(updated.referral_code, profile.referral_code);
});

test("saving an Apple display name does not mark username onboarding as complete", async () => {
  const admin = createClient("https://profiles.example", "test-only-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const request = new Request(input, init);
      assert.deepEqual(await request.json(), { display_name: "New Name" });
      return Response.json({ ...profile, display_name: "New Name", handle_set_at: null });
    } },
  });
  const updated = await updateProfile(profile.user_id, { display_name: "New Name" }, admin);
  assert.equal(updated.display_name, "New Name");
  assert.equal(updated.handle_set_at, null);
});

test("missing accounts and duplicate usernames return stable API errors", async () => {
  const admin = createClient("https://profiles.example", "test-only-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const request = new Request(input, init);
      return request.method === "GET" ? Response.json([]) : Response.json({
        code: "23505", message: "duplicate key", details: null, hint: null,
      }, { status: 409 });
    } },
  });
  await assert.rejects(readProfile(profile.user_id, admin),
    (error: unknown) => error instanceof ApiError && error.status === 401 && error.code === "profile_missing");
  await assert.rejects(updateProfile(profile.user_id, { handle: "taken" }, admin),
    (error: unknown) => error instanceof ApiError && error.status === 409 && error.code === "handle_taken");
});

test("profile routes authenticate before reads, writes, and deletion and allow PATCH preflights", async () => {
  const { GET, PATCH, DELETE, OPTIONS } = await import("@/app/api/v1/me/route");
  for (const [method, handler] of [["GET", GET], ["PATCH", PATCH], ["DELETE", DELETE]] as const) {
    const response = await handler(new Request("https://fitfight.app/api/v1/me", { method }), {
      params: Promise.resolve({}),
    });
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: "Missing bearer token", code: "unauthorized" });
  }
  const preflight = OPTIONS(new Request("https://fitfight.app/api/v1/me", { method: "OPTIONS" }));
  assert.match(preflight.headers.get("Access-Control-Allow-Methods") ?? "", /PATCH/);
});

test("profile HTTP routes use the verified owner, validate patches, and reject deleted accounts", async (t) => {
  const originalURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const originalKey = process.env.SUPABASE_SECRET_KEY;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://zstzbfocunthczzubggz.supabase.co";
  process.env.SUPABASE_SECRET_KEY = "test-only-key";
  t.after(() => {
    if (originalURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = originalURL;
    if (originalKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
    else process.env.SUPABASE_SECRET_KEY = originalKey;
  });
  let currentProfile = profile;
  let deleted = false;
  let writes = 0;
  t.mock.method(globalThis, "fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.hostname === "raw.githubusercontent.com") {
      const policy = { latest: null, review: null, enforced: false };
      return Response.json({ staging: policy, prod: policy });
    }
    if (url.pathname === "/auth/v1/user") {
      return Response.json({ id: profile.user_id, app_metadata: {}, user_metadata: {}, aud: "authenticated", created_at: "2026-09-01T00:00:00Z" });
    }
    assert.equal(url.pathname, "/rest/v1/profiles");
    assert.equal(url.searchParams.get("user_id"), `eq.${profile.user_id}`);
    assert.equal(url.searchParams.get("deleted_at"), "is.null");
    if (deleted) return Response.json([]);
    if (request.method === "PATCH") {
      writes += 1;
      currentProfile = profileSchema.parse({ ...currentProfile, ...await request.json() });
      return Response.json(currentProfile);
    }
    return Response.json(url.searchParams.get("select") === "user_id"
      ? [{ user_id: profile.user_id }] : [currentProfile]);
  });
  const token = [
    { alg: "HS256", typ: "JWT" }, { sub: profile.user_id, exp: Math.floor(Date.now() / 1000) + 3600 },
  ].map((part) => Buffer.from(JSON.stringify(part)).toString("base64url")).join(".") + ".dGVzdA";
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const { GET, PATCH } = await import("@/app/api/v1/me/route");
  const context = { params: Promise.resolve({}) };
  const read = await GET(new Request("https://fitfight.app/api/v1/me", { headers }), context);
  assert.equal(read.status, 200);
  assert.deepEqual(await read.json(), profile);
  const patch = await PATCH(new Request("https://fitfight.app/api/v1/me", {
    method: "PATCH", headers, body: JSON.stringify({ display_name: "New Name" }),
  }), context);
  assert.equal(patch.status, 200);
  assert.deepEqual(await patch.json(), { ...profile, display_name: "New Name" });

  for (const body of [{ user_id: "33333333-3333-4333-8333-333333333333", handle: "other" }, { handle: "bad-name" }]) {
    const rejected = await PATCH(new Request("https://fitfight.app/api/v1/me", {
      method: "PATCH", headers, body: JSON.stringify(body),
    }), context);
    assert.equal(rejected.status, 400);
  }
  assert.equal(writes, 1);
  deleted = true;
  const missing = await GET(new Request("https://fitfight.app/api/v1/me", { headers }), context);
  assert.equal(missing.status, 401);
  assert.deepEqual(await missing.json(), { error: "Invalid or deleted account", code: "profile_missing" });
});
