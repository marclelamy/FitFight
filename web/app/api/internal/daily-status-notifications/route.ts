import { ApiError, ERROR_CODES, apiRoute, json } from "@/lib/http";
import { enqueueDailyStatusNotifications } from "@/lib/supabase/queries/daily-status-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

function requireCron(request: Request): void {
  const secret = process.env.CRON_SECRET ?? process.env.FITFIGHT_CRON_SECRET;
  if (!secret) {
    throw new ApiError(503, ERROR_CODES.config, "Cron secret is not set");
  }
  const header = request.headers.get("authorization") ?? request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(\S+)/i.exec(header.trim());
  if (match?.[1] !== secret) {
    throw new ApiError(401, ERROR_CODES.unauthorized, "Unauthorized");
  }
}

async function handle(request: Request) {
  requireCron(request);
  const result = await enqueueDailyStatusNotifications();
  return json({ ok: true, ...result });
}

export const GET = apiRoute(handle);
export const POST = apiRoute(handle);
