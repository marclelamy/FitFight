import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { deleteFightPostComment } from "@/lib/supabase/queries/fight-post-engagement-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const DELETE = apiRoute<{ postID: string; commentID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  await deleteFightPostComment(
    userId,
    requireUuid(params.postID, "postID"),
    requireUuid(params.commentID, "commentID"),
  );
  return json({ deleted: true });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
