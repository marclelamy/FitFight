import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightMemberRow, FightSeriesRow, FightState } from "@/lib/types/database";
import { fightSummary, loadFight } from "./fight-access-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const OPEN_STATES: FightState[] = ["live", "scheduled", "inviting", "awaiting_final_sync"];

export async function leaveFight(
  userId: string,
  fightId: string,
  admin = createAdminClient(),
) {
  const fight = await loadFight(fightId, admin);
  if (fight.owner_id === userId) {
    throw new ApiError(403, ERROR_CODES.forbidden, "The owner cannot leave this fight");
  }

  const { data: memberData, error: memberError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", fightId)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  const member = memberData as Pick<FightMemberRow, "state"> | null;
  if (!member) {
    throw new ApiError(403, ERROR_CODES.forbidden, "You are not in this fight");
  }
  if (member.state === "withdrawn") {
    return fightSummary(fight);
  }
  if (member.state !== "accepted" && member.state !== "deferred") {
    throw new ApiError(409, ERROR_CODES.conflict, "This membership cannot be left");
  }

  const { error: withdrawError } = await admin
    .from("fight_members")
    .update({ state: "withdrawn" })
    .eq("fight_id", fightId)
    .eq("user_id", userId);
  if (withdrawError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not leave fight");
  }

  if (fight.series_id) {
    const { error: seriesMemberError } = await admin
      .from("fight_series_members")
      .update({ state: "withdrawn" })
      .eq("series_id", fight.series_id)
      .eq("user_id", userId);
    if (seriesMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not leave series");
    }

    const { data: seriesData, error: seriesError } = await admin
      .from("fight_series")
      .select("*")
      .eq("id", fight.series_id)
      .maybeSingle();
    if (seriesError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
    }
    const series = seriesData as FightSeriesRow | null;
    const currentId = series?.current_fight_id;
    if (currentId && currentId !== fightId) {
      const { error: currentError } = await admin
        .from("fight_members")
        .update({ state: "withdrawn" })
        .eq("fight_id", currentId)
        .eq("user_id", userId)
        .in("state", ["accepted", "deferred"]);
      if (currentError) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not leave current fight");
      }
      const current = await loadFight(currentId, admin);
      if (OPEN_STATES.includes(current.state)) {
        await recalculateFight(currentId);
      }
    }
  }

  if (OPEN_STATES.includes(fight.state)) {
    await recalculateFight(fightId);
  }

  return fightSummary(await loadFight(fightId, admin));
}
