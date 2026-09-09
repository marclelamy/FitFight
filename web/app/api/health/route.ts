import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyAppleSignInConfiguration } from "@/lib/apple/apple-sign-in";
import { verifyBackendReadiness } from "@/lib/supabase/queries/production-readiness-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async () => {
  const projectURL = process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "");
  const backend = projectURL === "https://pvqntpteehdvhqyctwum.supabase.co"
    ? "prod"
    : projectURL === "https://zstzbfocunthczzubggz.supabase.co"
      ? "staging"
      : null;
  if (!backend) {
    throw new ApiError(500, ERROR_CODES.config, "Supabase project is not configured");
  }

  verifyAppleSignInConfiguration();
  await verifyBackendReadiness();
  return json({ ok: true, backend, schema: "ready", profile_api: true });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
