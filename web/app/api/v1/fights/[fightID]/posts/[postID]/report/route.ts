import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { reportFightPost } from "@/lib/supabase/queries/fight-posts-supabase-query";
import { reportFightPostRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ fightID: string; postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = reportFightPostRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await reportFightPost(
    userId,
    requireUuid(params.fightID, "fightID"),
    requireUuid(params.postID, "postID"),
    parsed.data,
  ));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
