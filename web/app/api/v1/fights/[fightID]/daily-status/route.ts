import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readDailyStatusRecap } from "@/lib/supabase/queries/daily-status-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightID = requireUuid(params.fightID, "fightID");

  const recap = await readDailyStatusRecap(userId, fightID);
  if (!recap) {
    throw new ApiError(404, ERROR_CODES.not_found, "No daily status recap is available");
  }

  return json(recap);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
