import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { acceptMembership } from "@/lib/supabase/queries/accept-membership-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { membershipAcceptRequestSchema } from "@/lib/types/fights/join-start";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightId = requireUuid(params.fightID, "fightID");
  const parsed = membershipAcceptRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  const fight = await acceptMembership(userId, fightId, parsed.data.personalTarget, parsed.data.start);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
