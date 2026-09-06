import type { Sql } from "postgres";
import { isJoinCode, normalizeJoinCode } from "@/lib/domain/fights/join-code";
import { canDeferFightJoin, fightJoinMemberState } from "@/lib/domain/fights/join-start";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { FightRow, FightSeriesRow, ProfileRow } from "@/lib/types/database";
import type { JoinFightRequest, JoinableFightSummary } from "@/lib/types/fights/joinable-fight";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { fightSummary, loadSeries } from "./fight-access-supabase-query";
import { mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

export const JOINABLE_MEMBER_CAP = 50;
const JOIN_ATTEMPTS_PER_USER_HOUR = 10;
const JOIN_ATTEMPTS_PER_IP_HOUR = 30;

async function recordJoinAttempt(userId: string, clientIp: string | null, sql: Sql) {
  const [userCount] = await sql<{ n: number }[]>`
    select count(*)::int as n
    from private.fight_join_attempts
    where user_id = ${userId}
      and created_at >= now() - interval '1 hour'
  `;
  if (userCount.n >= JOIN_ATTEMPTS_PER_USER_HOUR) {
    throw new ApiError(429, ERROR_CODES.join_rate_limited, "Too many join attempts");
  }
  if (clientIp) {
    const [ipCount] = await sql<{ n: number }[]>`
      select count(*)::int as n
      from private.fight_join_attempts
      where client_ip = ${clientIp}
        and created_at >= now() - interval '1 hour'
    `;
    if (ipCount.n >= JOIN_ATTEMPTS_PER_IP_HOUR) {
      throw new ApiError(429, ERROR_CODES.join_rate_limited, "Too many join attempts");
    }
  }
  await sql`
    insert into private.fight_join_attempts (user_id, client_ip)
    values (${userId}, ${clientIp})
  `;
}

async function currentJoinableFight(
  series: FightSeriesRow,
  admin = createAdminClient(),
  now: Date = new Date(),
): Promise<FightRow | null> {
  if (!series.current_fight_id) {
    return null;
  }
  const { data, error } = await admin
    .from("fights")
    .select("*")
    .eq("id", series.current_fight_id)
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
  }
  let fight = data as FightRow | null;
  if (!fight) {
    return null;
  }
  if (series.recurring && !series.paused_at && Date.parse(fight.ends_at) <= now.getTime()) {
    const nextId = await mintNextRecurringFight(fight.id, admin, now);
    if (nextId && nextId !== fight.id) {
      const { data: nextData, error: nextError } = await admin
        .from("fights")
        .select("*")
        .eq("id", nextId)
        .maybeSingle();
      if (nextError) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load next fight");
      }
      fight = nextData as FightRow | null;
    }
  }
  return fight;
}

async function ownerHandle(ownerId: string, admin = createAdminClient()): Promise<string> {
  const { data, error } = await admin
    .from("profiles")
    .select("user_id, handle, display_name, time_zone")
    .eq("user_id", ownerId)
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load owner");
  }
  const profile = data as ProfileRow | null;
  return profile?.handle ?? "user";
}

const ROSTER_STATES = ["accepted", "deferred"] as const;

async function rosterMemberCount(fightId: string, admin = createAdminClient()): Promise<number> {
  const { count, error } = await admin
    .from("fight_members")
    .select("fight_id", { count: "exact", head: true })
    .eq("fight_id", fightId)
    .in("state", [...ROSTER_STATES]);
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not count members");
  }
  return count ?? 0;
}

async function isRosterMember(
  fightId: string,
  userId: string,
  admin = createAdminClient(),
): Promise<boolean> {
  const { data, error } = await admin
    .from("fight_members")
    .select("fight_id")
    .eq("fight_id", fightId)
    .eq("user_id", userId)
    .in("state", [...ROSTER_STATES])
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  return Boolean(data);
}

async function toSummary(
  series: FightSeriesRow,
  fight: FightRow,
  userId: string,
  admin = createAdminClient(),
  now: Date = new Date(),
): Promise<JoinableFightSummary> {
  if (series.visibility !== "joinable" || !series.join_code) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  const [handle, memberCount, alreadyMember] = await Promise.all([
    ownerHandle(series.owner_id, admin),
    rosterMemberCount(fight.id, admin),
    isRosterMember(fight.id, userId, admin),
  ]);
  return {
    fightId: fight.id,
    seriesId: series.id,
    name: series.name,
    joinCode: series.join_code,
    ownerHandle: handle,
    actionText: fight.action_text,
    startsAt: fight.starts_at,
    endsAt: fight.ends_at,
    memberCount,
    recurring: series.recurring,
    alreadyMember,
    canJoinNext: !alreadyMember && canDeferFightJoin({
      recurring: series.recurring,
      paused: Boolean(series.paused_at),
      startsAt: fight.starts_at,
      now,
    }),
  };
}

export async function listJoinableFights(
  userId: string,
  admin = createAdminClient(),
  now: Date = new Date(),
): Promise<JoinableFightSummary[]> {
  const { data, error } = await admin
    .from("fight_series")
    .select("*")
    .eq("visibility", "joinable")
    .is("paused_at", null)
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not list joinable fights");
  }
  const summaries: JoinableFightSummary[] = [];
  for (const row of (data ?? []) as FightSeriesRow[]) {
    const fight = await currentJoinableFight(row, admin, now);
    if (!fight) {
      continue;
    }
    if (fight.state === "final" || fight.state === "cancelled" || fight.state === "awaiting_final_sync") {
      continue;
    }
    summaries.push(await toSummary(row, fight, userId, admin, now));
    if (summaries.length >= 50) {
      break;
    }
  }
  return summaries;
}

export async function getJoinableFightByCode(
  userId: string,
  rawCode: string,
  admin = createAdminClient(),
  now: Date = new Date(),
): Promise<JoinableFightSummary> {
  const code = normalizeJoinCode(rawCode);
  if (!isJoinCode(code)) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  const { data, error } = await admin
    .from("fight_series")
    .select("*")
    .eq("join_code", code)
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
  }
  const series = data as FightSeriesRow | null;
  if (!series || series.visibility !== "joinable" || series.paused_at) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  const fight = await currentJoinableFight(series, admin, now);
  if (!fight) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  if (fight.state === "final" || fight.state === "cancelled" || fight.state === "awaiting_final_sync") {
    throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
  }
  return toSummary(series, fight, userId, admin, now);
}

export async function joinFight(
  userId: string,
  input: JoinFightRequest,
  clientIp: string | null = null,
  admin = createAdminClient(),
  now: Date = new Date(),
  sql: Sql = createDatabaseClient(),
) {
  await recordJoinAttempt(userId, clientIp, sql);

  let series: FightSeriesRow;
  if (input.code) {
    const code = normalizeJoinCode(input.code);
    if (!isJoinCode(code)) {
      throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    const { data, error } = await admin
      .from("fight_series")
      .select("*")
      .eq("join_code", code)
      .maybeSingle();
    if (error) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
    }
    if (!data) {
      throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    series = data as FightSeriesRow;
  } else {
    const { data: fightData, error: fightError } = await admin
      .from("fights")
      .select("*")
      .eq("id", input.fightId)
      .maybeSingle();
    if (fightError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
    }
    const listed = fightData as FightRow | null;
    if (!listed?.series_id) {
      throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    series = await loadSeries(listed.series_id, admin);
  }

  if (series.visibility !== "joinable" || series.paused_at) {
    throw new ApiError(403, ERROR_CODES.fight_not_joinable, "This fight is invite-only");
  }

  const fight = await currentJoinableFight(series, admin, now);
  if (!fight) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  if (["final", "cancelled", "awaiting_final_sync"].includes(fight.state)) {
    throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
  }

  const { data: existingMember, error: memberLookupError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", fight.id)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberLookupError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  if (existingMember?.state === "accepted" || existingMember?.state === "deferred") {
    return fightSummary(fight);
  }

  const count = await rosterMemberCount(fight.id, admin);
  if (count >= JOINABLE_MEMBER_CAP) {
    throw new ApiError(409, ERROR_CODES.fight_full, "This fight is full");
  }

  const canDefer = canDeferFightJoin({
    recurring: series.recurring,
    paused: Boolean(series.paused_at),
    startsAt: fight.starts_at,
    now,
  });
  const memberState = fightJoinMemberState(input.start, canDefer);
  if (!memberState) {
    throw new ApiError(409, ERROR_CODES.conflict, "This fight does not have a next round to join");
  }

  const source = await ensureAppleHealthSource(userId, { admin });
  const nowIso = now.toISOString();
  if (!existingMember) {
    const { error: insertError } = await admin.from("fight_members").insert({
      fight_id: fight.id,
      user_id: userId,
      state: memberState,
      accepted_at: nowIso,
      selected_source_id: source.id,
      source_label: source.sourceLabel,
      acceptance_copy_version: 1,
    });
    if (insertError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not join fight");
    }
  } else {
    const { error: updateError } = await admin
      .from("fight_members")
      .update({
        state: memberState,
        accepted_at: nowIso,
        selected_source_id: source.id,
        source_label: source.sourceLabel,
        acceptance_copy_version: 1,
      })
      .eq("fight_id", fight.id)
      .eq("user_id", userId);
    if (updateError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not join fight");
    }
  }

  const { error: seriesMemberError } = await admin.from("fight_series_members").upsert({
    series_id: series.id,
    user_id: userId,
    state: "accepted",
    joined_at: nowIso,
  });
  if (seriesMemberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not join series");
  }

  if (memberState === "accepted") {
    await recalculateFight(fight.id, now);
  }
  return fightSummary(await (async () => {
    const { data } = await admin.from("fights").select("id, state").eq("id", fight.id).maybeSingle();
    return (data as Pick<FightRow, "id" | "state"> | null) ?? fight;
  })());
}
