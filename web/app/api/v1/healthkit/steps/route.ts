import { apiRoute, corsPreflight, json, readJson, measureRequestStage } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { syncHealthKitAggregates } from "@/lib/supabase/queries/healthkit-aggregates-supabase-query";
import { healthKitAggregateSyncSchema } from "@/lib/types/healthkit/healthkit-aggregate";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request, { timing }) => {
  const { userId } = await measureRequestStage(timing, "auth", () => verifyUser(request));
  const input = healthKitAggregateSyncSchema.parse(await readJson(request));
  return json(await measureRequestStage(timing, "db", () => syncHealthKitAggregates(userId, input)));
}, "healthkit_upload");

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
