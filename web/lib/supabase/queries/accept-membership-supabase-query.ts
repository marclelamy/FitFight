import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightMemberRow } from "@/lib/types/database";
import type { FightJoinStart } from "@/lib/types/fights/join-start";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { fightSummary, joinMemberStateForFight, loadFight } from "./fight-access-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

/** In-app accept: the signed-in User is already an invited member. No raw token. */
export async function acceptMembership(
  userId: string,
  fightId: string,
  personalTarget?: number,
  start: FightJoinStart = "now",
  now: Date = new Date(),
) {
  const admin = createAdminClient();
  const fight = await loadFight(fightId, admin);
  if (fight.state === "cancelled" || fight.state === "final") {
    throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
  }

  const { data: existingMember, error: memberLookupError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", fightId)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberLookupError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  const member = existingMember as Pick<FightMemberRow, "state"> | null;
  if (!member) {
    throw new ApiError(403, ERROR_CODES.forbidden, "You were not invited to this fight");
  }
  if (member.state === "accepted" || member.state === "deferred") {
    return fightSummary(fight);
  }
  if (member.state !== "invited") {
    throw new ApiError(409, ERROR_CODES.conflict, "This membership cannot be accepted");
  }

  const memberState = await joinMemberStateForFight(fight, start, now, admin);
  const source = await ensureAppleHealthSource(userId, { admin });
  const nowIso = now.toISOString();
  const { error: updateMemberError } = await admin
    .from("fight_members")
    .update({
      state: memberState,
      accepted_at: nowIso,
      selected_source_id: source.id,
      source_label: source.sourceLabel,
      personal_target: personalTarget ?? null,
      target_origin: personalTarget !== undefined ? "user" : null,
      acceptance_copy_version: 1,
    })
    .eq("fight_id", fightId)
    .eq("user_id", userId);
  if (updateMemberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not accept fight");
  }

  await admin
    .from("fight_invites")
    .update({ accepted_at: nowIso })
    .eq("fight_id", fightId)
    .eq("invited_user_id", userId)
    .is("accepted_at", null);

  if (memberState === "accepted" && ["live", "scheduled", "awaiting_final_sync"].includes(fight.state)) {
    await recalculateFight(fight.id, now);
  }

  if (fight.series_id) {
    const { error: seriesMemberError } = await admin.from("fight_series_members").upsert({
      series_id: fight.series_id,
      user_id: userId,
      state: "accepted",
      joined_at: nowIso,
    });
    if (seriesMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not join series");
    }
  }

  return fightSummary(await loadFight(fight.id, admin));
}
