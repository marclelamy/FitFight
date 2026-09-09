import assert from "node:assert/strict";
import { test } from "node:test";
import { GET } from "@/app/api/app-release/route";
import { ApiError } from "@/lib/http";
import { appReleasePolicy, requireLatestAppRelease } from "./app-release";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";

const manifest = {
  staging: {
    latest: { version: "1.0.0", build: 160, update_url: "itms-beta://" },
    review: null,
    enforced: true,
  },
  prod: {
    latest: { version: "1.0.0", build: 150, update_url: "https://apps.apple.com/app/id1234" },
    review: { version: "1.1.0", build: 165, update_url: "https://apps.apple.com/app/id1234" },
    enforced: true,
  },
};

test("only the exact latest staging version and build can call the API", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://zstzbfocunthczzubggz.supabase.co";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  const fetch = t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
  for (const headers of [
    undefined,
    { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "159" },
    { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "161" },
    { "X-FitFight-Version": "1.1.0", "X-FitFight-Build": "160" },
    { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "0160" },
  ]) {
    await assert.rejects(requireLatestAppRelease(new Request("https://staging.fitfight.app/api/v1/fights", {
      headers,
    })), (error: unknown) => error instanceof ApiError && error.status === 426 && error.code === "update_required");
  }
  await requireLatestAppRelease(new Request("https://staging.fitfight.app/api/v1/fights", {
    headers: { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "160" },
  }));
  assert.equal(fetch.mock.calls[0].arguments[1]?.cache, "no-store");
});

test("production admits its live build and the selected Apple review candidate, never a staging build", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://pvqntpteehdvhqyctwum.supabase.co";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
  for (const [version, build] of [["1.0.0", "150"], ["1.1.0", "165"]]) {
    await requireLatestAppRelease(new Request("https://fitfight.app/api/v1/fights", {
      headers: { "X-FitFight-Version": version, "X-FitFight-Build": build },
    }));
  }
  await assert.rejects(requireLatestAppRelease(new Request("https://fitfight.app/api/v1/fights", {
    headers: { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "160" },
  })), (error: unknown) => error instanceof ApiError && error.status === 426);
});

test("a registered TestFlight review build can run before it becomes mandatory for testers", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://zstzbfocunthczzubggz.supabase.co";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  t.mock.method(globalThis, "fetch", async () => Response.json({
    ...manifest,
    staging: { ...manifest.staging, review: { version: "1.0.0", build: 170, update_url: "itms-beta://" } },
  }));
  for (const build of ["160", "170"]) {
    await requireLatestAppRelease(new Request("https://staging.fitfight.app/api/v1/fights", {
      headers: { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": build },
    }));
  }
});

test("the public version check is available without auth and never cached", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://pvqntpteehdvhqyctwum.supabase.co/";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
  const response = await GET(new Request("https://fitfight.app/api/app-release"), { params: Promise.resolve({}) });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), manifest.prod);
});

test("unavailable or malformed release metadata never admits a client", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://pvqntpteehdvhqyctwum.supabase.co";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  for (const response of [
    new Response("Unavailable", { status: 503 }),
    new Response("invalid json"),
    Response.json({ prod: { latest: { version: "1.0.0", build: "150" } } }),
    Response.json({ ...manifest, prod: { ...manifest.prod, latest: { ...manifest.prod.latest, update_url: "https://evil.example" } } }),
  ]) {
    const fetch = t.mock.method(globalThis, "fetch", async () => response);
    await assert.rejects(appReleasePolicy(), (error: unknown) => error instanceof ApiError && error.status === 503);
    fetch.mock.restore();
  }
  t.mock.method(globalThis, "fetch", async () => { throw new Error("offline"); });
  await assert.rejects(appReleasePolicy(), (error: unknown) => error instanceof ApiError && error.status === 503);
});

test("old authenticated binaries are rejected before database or auth-provider calls", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://zstzbfocunthczzubggz.supabase.co";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  const fetch = t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
  await assert.rejects(verifyUser(new Request("https://staging.fitfight.app/api/v1/fights", {
    headers: { Authorization: "Bearer old-app-token" },
  })), (error: unknown) => error instanceof ApiError && error.status === 426);
  assert.equal(fetch.mock.callCount(), 1);
});

test("the first deployment preserves old clients until a build containing the gate is installable", async (t) => {
  const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://zstzbfocunthczzubggz.supabase.co";
  t.after(() => {
    if (previousProject === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
  });
  t.mock.method(globalThis, "fetch", async () => Response.json({
    ...manifest, staging: { ...manifest.staging, enforced: false },
  }));
  await requireLatestAppRelease(new Request("https://staging.fitfight.app/api/v1/fights"));
});
