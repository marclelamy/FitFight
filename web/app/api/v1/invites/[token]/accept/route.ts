import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { acceptInvite } from "@/lib/supabase/queries/accept-invite-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { membershipAcceptRequestSchema } from "@/lib/types/fights/join-start";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ token: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = membershipAcceptRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  const fight = await acceptInvite(userId, params.token, parsed.data.personalTarget, parsed.data.start);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
