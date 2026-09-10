import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { setFightPostReaction } from "@/lib/supabase/queries/fight-post-engagement-supabase-query";
import { setFightPostReactionRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = setFightPostReactionRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await setFightPostReaction(
    userId,
    requireUuid(params.postID, "postID"),
    parsed.data.emoji,
  ));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
