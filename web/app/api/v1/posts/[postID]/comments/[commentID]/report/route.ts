import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { reportFightPostComment } from "@/lib/supabase/queries/fight-post-engagement-supabase-query";
import { reportFightPostCommentRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ postID: string; commentID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = reportFightPostCommentRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await reportFightPostComment(
    userId,
    requireUuid(params.postID, "postID"),
    requireUuid(params.commentID, "commentID"),
    parsed.data,
  ));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
