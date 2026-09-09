import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { listFeedPeople } from "@/lib/supabase/queries/fight-posts-supabase-query";
import { listFeedPeopleQuerySchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const search = new URL(request.url).searchParams;
  const parsed = listFeedPeopleQuerySchema.safeParse({
    ...(search.get("main") ? { main: search.get("main") } : {}),
    ...(search.get("fight_ids") ? { fight_ids: search.get("fight_ids") } : {}),
  });
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await listFeedPeople(userId, parsed.data));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
