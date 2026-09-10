import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { deleteFightPost } from "@/lib/supabase/queries/fight-posts-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const DELETE = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  await deleteFightPost(userId, undefined, requireUuid(params.postID, "postID"));
  return json({ deleted: true });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
