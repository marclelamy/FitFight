import { hashInviteToken } from "@/lib/domain/invites/token";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightInviteRow, FightMemberRow } from "@/lib/types/database";
import type { FightJoinStart } from "@/lib/types/fights/join-start";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { fightSummary, joinMemberStateForFight, loadFight } from "./fight-access-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

export async function acceptInvite(
  userId: string,
  rawToken: string,
  personalTarget?: number,
  start: FightJoinStart = "now",
  now: Date = new Date(),
) {
  const token = decodeURIComponent(rawToken).trim();
  if (!token) {
    throw new ApiError(400, ERROR_CODES.validation, "Missing invite token");
  }

  const admin = createAdminClient();
  const tokenHash = hashInviteToken(token);
  const { data: inviteData, error: inviteError } = await admin
    .from("fight_invites")
    .select("id, fight_id, invited_user_id, token_hash, expires_at, revoked_at, accepted_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (inviteError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load invite");
  }
  const invite = inviteData as FightInviteRow | null;
  if (!invite) {
    throw new ApiError(404, ERROR_CODES.not_found, "Invite not found");
  }
  if (invite.revoked_at) {
    throw new ApiError(410, ERROR_CODES.invite_revoked, "Invite was revoked");
  }
  if (new Date(invite.expires_at).getTime() <= now.getTime()) {
    throw new ApiError(410, ERROR_CODES.invite_expired, "Invite expired");
  }
  if (invite.invited_user_id && invite.invited_user_id !== userId) {
    throw new ApiError(403, ERROR_CODES.invite_wrong_user, "This invite belongs to another user");
  }

  const fight = await loadFight(invite.fight_id, admin);
  if (fight.state === "cancelled" || fight.state === "final") {
    throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
  }

  const { data: existingMember, error: memberLookupError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", invite.fight_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberLookupError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  const member = existingMember as Pick<FightMemberRow, "state"> | null;
  if (member?.state === "accepted" || member?.state === "deferred") {
    return fightSummary(fight);
  }

  const memberState = await joinMemberStateForFight(fight, start, now, admin);
  const source = await ensureAppleHealthSource(userId, { admin });
  const nowIso = now.toISOString();
  const memberPatch = {
    state: memberState,
    accepted_at: nowIso,
    selected_source_id: source.id,
    source_label: source.sourceLabel,
    personal_target: personalTarget ?? null,
    target_origin: personalTarget !== undefined ? "user" : null,
    acceptance_copy_version: 1,
  };

  if (member) {
    const { error: updateMemberError } = await admin
      .from("fight_members")
      .update(memberPatch)
      .eq("fight_id", invite.fight_id)
      .eq("user_id", userId);
    if (updateMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not accept invite");
    }
  } else {
    const { error: insertMemberError } = await admin.from("fight_members").insert({
      fight_id: invite.fight_id,
      user_id: userId,
      ...memberPatch,
    });
    if (insertMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not accept invite");
    }
  }

  const { error: inviteUpdateError } = await admin
    .from("fight_invites")
    .update({ accepted_at: nowIso })
    .eq("id", invite.id);
  if (inviteUpdateError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not mark invite accepted");
  }

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
