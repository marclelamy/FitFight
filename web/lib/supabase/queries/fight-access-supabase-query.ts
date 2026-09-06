import type { SupabaseClient } from "@supabase/supabase-js";
import { canDeferFightJoin, fightJoinMemberState } from "@/lib/domain/fights/join-start";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightRow, FightSeriesRow } from "@/lib/types/database";
import type { FightJoinStart } from "@/lib/types/fights/join-start";

export async function loadFight(
  fightId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<FightRow> {
  const { data, error } = await admin.from("fights").select("*").eq("id", fightId).maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
  }
  if (!data) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  return data as FightRow;
}

export async function loadSeries(
  seriesId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<FightSeriesRow> {
  const { data, error } = await admin.from("fight_series").select("*").eq("id", seriesId).maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
  }
  if (!data) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  return data as FightSeriesRow;
}

export async function loadOwnedFight(
  fightId: string,
  userId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<FightRow> {
  const fight = await loadFight(fightId, admin);
  if (fight.owner_id !== userId) {
    throw new ApiError(403, ERROR_CODES.forbidden, "Only the owner can do this");
  }
  return fight;
}

export function fightSummary(fight: Pick<FightRow, "id" | "state">) {
  return { id: fight.id, state: fight.state };
}

export async function joinMemberStateForFight(
  fight: FightRow,
  start: FightJoinStart,
  now: Date = new Date(),
  admin: SupabaseClient = createAdminClient(),
): Promise<"accepted" | "deferred"> {
  let recurring = false;
  let paused = false;
  if (fight.series_id) {
    const series = await loadSeries(fight.series_id, admin);
    recurring = series.recurring;
    paused = Boolean(series.paused_at);
  }
  const memberState = fightJoinMemberState(
    start,
    canDeferFightJoin({ recurring, paused, startsAt: fight.starts_at, now }),
  );
  if (!memberState) {
    throw new ApiError(409, ERROR_CODES.conflict, "This fight does not have a next round to join");
  }
  return memberState;
}

