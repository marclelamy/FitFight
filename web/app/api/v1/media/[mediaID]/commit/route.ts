import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { commitMediaUpload } from "@/lib/supabase/queries/media-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ mediaID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  return json({
    media: await commitMediaUpload(userId, requireUuid(params.mediaID, "mediaID")),
  });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
