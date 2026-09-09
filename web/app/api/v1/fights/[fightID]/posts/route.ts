import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createFightPost, listFightPosts } from "@/lib/supabase/queries/fight-posts-supabase-query";
import {
  createFightPostRequestSchema,
  listFightPostsQuerySchema,
} from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightId = requireUuid(params.fightID, "fightID");
  const search = new URL(request.url).searchParams;
  const parsed = listFightPostsQuerySchema.safeParse({
    ...(search.get("cursor") ? { cursor: search.get("cursor") } : {}),
    ...(search.get("limit") ? { limit: search.get("limit") } : {}),
  });
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await listFightPosts(userId, fightId, parsed.data));
});

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = createFightPostRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await createFightPost(userId, requireUuid(params.fightID, "fightID"), parsed.data), 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
