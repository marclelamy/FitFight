import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
  createFightPostComment,
  listFightPostComments,
} from "@/lib/supabase/queries/fight-post-engagement-supabase-query";
import {
  createFightPostCommentRequestSchema,
  listFightPostCommentsQuerySchema,
} from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const search = new URL(request.url).searchParams;
  const parsed = listFightPostCommentsQuerySchema.safeParse({
    ...(search.get("cursor") ? { cursor: search.get("cursor") } : {}),
    ...(search.get("limit") ? { limit: search.get("limit") } : {}),
  });
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await listFightPostComments(userId, requireUuid(params.postID, "postID"), parsed.data));
});

export const POST = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = createFightPostCommentRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(
    await createFightPostComment(userId, requireUuid(params.postID, "postID"), parsed.data),
    201,
  );
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
