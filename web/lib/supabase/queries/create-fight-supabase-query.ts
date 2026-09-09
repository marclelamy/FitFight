import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightRow, ProfileRow } from "@/lib/types/database";
import { fightVisibilitySchema } from "@/lib/types/fights/joinable-fight";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { createInvite, lookupProfileByHandle } from "./create-invite-supabase-query";
import { fightSummary } from "./fight-access-supabase-query";

const dateTime = z.string().refine((value) => Number.isFinite(Date.parse(value)), "must be a date-time");

export function storedFightIdentity(
  name: string | undefined,
  actionText: string | undefined,
): { name: string; actionText: string | null } {
  const title = name?.trim() ?? "";
  const action = actionText?.trim() ?? "";
  return {
    name: title || action || "Steps Fight",
    actionText: action.length > 0 ? action : null,
  };
}

export const createFightSchema = z
  .object({
    name: z.string().trim().max(120).optional(),
    startsAt: dateTime,
    endsAt: dateTime,
    timeZone: z.string().min(1),
    outcomeRule: z.enum(["highest_total", "proportional", "hit_your_goal"]),
    goalPolicy: z.enum(["shared", "personal"]).default("shared"),
    defaultGoalValue: z.number().optional(),
    stakeKind: z.enum(["bragging", "money", "action"]),
    stakeMinor: z.number().int().min(0).optional(),
    currency: z.string().default("USD"),
    actionText: z.string().trim().max(120).optional(),
    inviteHandles: z.array(z.string()).optional(),
    start: z.enum(["now", "scheduled"]).default("now"),
    metric: z.literal("steps").optional(),
    visibility: fightVisibilitySchema.default("invite_only"),
    recurring: z.boolean().default(true),
  })
  .superRefine((value, ctx) => {
    const starts = Date.parse(value.startsAt);
    const ends = Date.parse(value.endsAt);
    if (!Number.isFinite(starts) || !Number.isFinite(ends)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "startsAt and endsAt must be dates" });
      return;
    }
    if (ends <= starts) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "endsAt must be after startsAt" });
    }
    const handles = (value.inviteHandles ?? [])
      .map((handle) => handle.trim())
      .filter((handle) => handle.length > 0);
    if (value.visibility === "invite_only" && handles.length === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["inviteHandles"],
        message: "Invite-only fights need at least one username",
      });
    }
  });

export type CreateFightInput = z.infer<typeof createFightSchema>;

const IDEMPOTENCY_WINDOW_MS = 2 * 60 * 1000;
const JOIN_CODE_ATTEMPTS = 8;

function initialState(input: CreateFightInput): "live" | "scheduled" | "inviting" {
  if (input.start === "now") {
    return "live";
  }
  if ((input.inviteHandles?.length ?? 0) > 0) {
    return "inviting";
  }
  return "scheduled";
}

async function allocateJoinCode(admin: SupabaseClient): Promise<string> {
  for (let attempt = 0; attempt < JOIN_CODE_ATTEMPTS; attempt += 1) {
    const code = randomJoinCode();
    const { data, error } = await admin.from("fight_series").select("id").eq("join_code", code).maybeSingle();
    if (error) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not allocate join code");
    }
    if (!data) {
      return code;
    }
  }
  throw new ApiError(500, ERROR_CODES.db_error, "Could not allocate join code");
}

export async function createFight(userId: string, input: CreateFightInput) {
  if (input.metric && input.metric !== "steps") {
    throw new ApiError(400, ERROR_CODES.invalid_metric, "metric must be steps");
  }

  const admin = createAdminClient();
  const { data: profileData, error: profileError } = await admin
    .from("profiles")
    .select("user_id, handle, display_name, time_zone")
    .eq("user_id", userId)
    .maybeSingle();
  if (profileError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load profile");
  }
  const profile = profileData as ProfileRow | null;
  if (!profile) {
    throw new ApiError(400, ERROR_CODES.profile_missing, "Profile is missing");
  }

  const startsAt = new Date(input.startsAt).toISOString();
  const endsAt = new Date(input.endsAt).toISOString();
  const since = new Date(Date.now() - IDEMPOTENCY_WINDOW_MS).toISOString();
  const stored = storedFightIdentity(input.name, input.actionText);

  const { data: existingData, error: existingError } = await admin
    .from("fights")
    .select("id, state")
    .eq("owner_id", userId)
    .eq("name", stored.name)
    .eq("starts_at", startsAt)
    .eq("ends_at", endsAt)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existingError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not check existing fight");
  }
  if (existingData) {
    return fightSummary(existingData as Pick<FightRow, "id" | "state">);
  }

  const handles = (input.inviteHandles ?? [])
    .map((handle) => handle.trim())
    .filter((handle) => handle.length > 0);
  for (const handle of handles) {
    const invitee = await lookupProfileByHandle(admin, handle);
    if (invitee.user_id === userId) {
      throw new ApiError(400, ERROR_CODES.validation, "Cannot invite yourself");
    }
  }
  const state = initialState({ ...input, inviteHandles: handles });
  const source = await ensureAppleHealthSource(userId, { admin });
  const needsSeries = input.visibility === "joinable" || input.recurring;
  let seriesId: string | null = null;
  if (needsSeries) {
    const durationSeconds = Math.round((Date.parse(endsAt) - Date.parse(startsAt)) / 1000);
    const joinCode = input.visibility === "joinable" ? await allocateJoinCode(admin) : null;
    const { data: series, error: seriesError } = await admin
      .from("fight_series")
      .insert({
        owner_id: userId,
        join_code: joinCode,
        visibility: input.visibility,
        recurring: input.recurring,
        duration_seconds: durationSeconds,
        name: stored.name,
        action_text: stored.actionText,
        time_zone: input.timeZone,
      })
      .select("id")
      .single();
    if (seriesError || !series) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not create fight series");
    }
    seriesId = series.id as string;
  }

  const { data: inserted, error: insertError } = await admin
    .from("fights")
    .insert({
      owner_id: userId,
      name: stored.name,
      state,
      starts_at: startsAt,
      ends_at: endsAt,
      time_zone: input.timeZone,
      metric: "steps",
      outcome_rule: input.outcomeRule,
      goal_policy: input.goalPolicy,
      default_goal_value: input.defaultGoalValue ?? null,
      stake_kind: input.stakeKind,
      stake_minor: input.stakeMinor ?? null,
      currency: input.stakeKind === "money" ? input.currency : input.currency ?? null,
      action_text: stored.actionText,
      series_id: seriesId,
    })
    .select("id, state")
    .single();
  if (insertError || !inserted) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not create fight");
  }

  if (seriesId) {
    const { error: currentError } = await admin
      .from("fight_series")
      .update({ current_fight_id: inserted.id })
      .eq("id", seriesId);
    if (currentError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not attach series to fight");
    }
  }

  const nowIso = new Date().toISOString();
  const { error: memberError } = await admin.from("fight_members").insert({
    fight_id: inserted.id,
    user_id: userId,
    state: "accepted",
    accepted_at: nowIso,
    selected_source_id: source.id,
    source_label: source.sourceLabel,
  });
  if (memberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not add owner as member");
  }

  if (seriesId) {
    const { error: seriesMemberError } = await admin.from("fight_series_members").insert({
      series_id: seriesId,
      user_id: userId,
      state: "accepted",
      joined_at: nowIso,
    });
    if (seriesMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not add owner to series");
    }
  }

  for (const handle of handles) {
    await createInvite(userId, inserted.id as string, handle);
  }

  return fightSummary(inserted as Pick<FightRow, "id" | "state">);
}
