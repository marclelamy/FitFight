import { apiRoute, corsPreflight, json } from "@/lib/http";
import { isApnsConfigured } from "@/lib/apns/apns-config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async () => {
  return json({ apns_configured: isApnsConfigured() });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
