import { apiRoute, corsPreflight, json, measureRequestStage } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getProviderUploadContext } from "@/lib/supabase/queries/provider-uploads-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request, { timing }) => {
  const { userId } = await measureRequestStage(timing, "auth", () => verifyUser(request));
  return json(await measureRequestStage(timing, "db", () => getProviderUploadContext(userId)));
}, "healthkit_context");

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
