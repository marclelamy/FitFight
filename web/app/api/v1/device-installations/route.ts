import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { registerDeviceInstallation } from "@/lib/supabase/queries/device-installations-supabase-query";
import { registerDeviceInstallationRequestSchema } from "@/lib/types/notifications/device-installation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const input = registerDeviceInstallationRequestSchema.parse(await readJson(request));
  return json(await registerDeviceInstallation(userId, input));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
