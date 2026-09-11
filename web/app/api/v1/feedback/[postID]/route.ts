import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { isFitFightAdmin, readAdminViewer } from "@/lib/admin/is-fitfight-admin";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getFeedbackPost } from "@/lib/supabase/queries/feedback-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const postId = requireUuid(params.postID, "postID");
  const detail = await getFeedbackPost(userId, postId);
  const viewer = await readAdminViewer(userId);
  return json({
    ...detail,
    can_launch_fix: isFitFightAdmin(viewer),
  });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
