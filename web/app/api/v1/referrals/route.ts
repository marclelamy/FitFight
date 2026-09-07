import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { claimReferral } from "@/lib/supabase/queries/referrals-supabase-query";
import { claimReferralRequestSchema } from "@/lib/types/referrals/referral";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = claimReferralRequestSchema.safeParse(await readJson(request, 1024));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await claimReferral(userId, parsed.data));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
