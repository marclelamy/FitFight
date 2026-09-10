import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { listFightPosts } from "@/lib/supabase/queries/fight-posts-supabase-query";
import { listFightPostsQuerySchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const search = new URL(request.url).searchParams;
  const parsed = listFightPostsQuerySchema.safeParse({
    ...(search.get("cursor") ? { cursor: search.get("cursor") } : {}),
    ...(search.get("limit") ? { limit: search.get("limit") } : {}),
    ...(search.get("scope") ? { scope: search.get("scope") } : {}),
  });
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await listFightPosts(userId, undefined, parsed.data));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
