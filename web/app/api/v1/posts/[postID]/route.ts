import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { deleteFightPost, updateFightPost } from "@/lib/supabase/queries/fight-posts-supabase-query";
import { updateFightPostRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const PATCH = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = updateFightPostRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await updateFightPost(userId, requireUuid(params.postID, "postID"), parsed.data));
});

export const DELETE = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  await deleteFightPost(userId, undefined, requireUuid(params.postID, "postID"));
  return json({ deleted: true });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
