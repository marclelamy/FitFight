import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createMediaUpload } from "@/lib/supabase/queries/media-supabase-query";
import { createMediaUploadRequestSchema } from "@/lib/types/media/media";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = createMediaUploadRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await createMediaUpload(userId, parsed.data), 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
