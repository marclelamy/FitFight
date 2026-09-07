import assert from "node:assert/strict";
import { test } from "node:test";
import { POST } from "@/app/api/v1/referrals/route";
import { claimReferralRequestSchema } from "@/lib/types/referrals/referral";

test("referral claims accept only an opaque code, never caller-supplied identities", () => {
  const code = "11111111-1111-4111-8111-111111111111";
  assert.deepEqual(claimReferralRequestSchema.parse({ code }), { code });
  for (const input of [
    {}, { code: "not-a-code" }, { code: "https://example.com" },
    { code, referred_user_id: code }, { code, referrer_user_id: code },
  ]) {
    assert.equal(claimReferralRequestSchema.safeParse(input).success, false);
  }
});

test("referral claims require authentication before accessing the database", async () => {
  const response = await POST(new Request("https://staging.fitfight.app/api/v1/referrals", {
    method: "POST",
  }), { params: Promise.resolve({}) });
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("cache-control"), "no-store");
});
