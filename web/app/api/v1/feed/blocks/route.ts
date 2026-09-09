import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { blockFeedAuthor } from "@/lib/supabase/queries/fight-posts-supabase-query";
import { blockFeedAuthorRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = blockFeedAuthorRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await blockFeedAuthor(userId, parsed.data.user_id));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
