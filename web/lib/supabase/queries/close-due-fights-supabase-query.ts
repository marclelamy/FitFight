import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { fightNeedsCloserTick } from "@/lib/scoring/fight-clock";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { fightMaintenanceCandidateSchema, userFightMaintenanceSchema, type FightMaintenanceCandidate } from "@/lib/types/fights/fight-snapshot";
import { mintDueRecurringFights, mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const DUE_STATES = ["live", "scheduled", "awaiting_final_sync"] as const;
const BATCH = 25;

export type CloseDueResult = {
  checked: number;
  closed: number;
  fightIds: string[];
};

function dueIds(rows: FightMaintenanceCandidate[], nowMs: number): string[] {
  return rows
    .filter((row) =>
      fightNeedsCloserTick({
        state: row.state,
        nowMs,
        startsAtMs: Date.parse(row.starts_at),
        endsAtMs: Date.parse(row.ends_at),
      }),
    )
    .map((row) => row.id);
}

async function recalculateIds(
  fightIds: string[],
  now: Date,
  database?: Sql,
): Promise<string[]> {
  const closed: string[] = [];
  for (const fightId of fightIds.slice(0, BATCH)) {
    await recalculateFight(fightId, now, database);
    closed.push(fightId);
  }
  return closed;
}

/** Server job: walk fights whose clock can move, using `now` so tests fake time. */
export async function closeDueFights(
  admin: SupabaseClient = createAdminClient(),
  now: Date = new Date(),
): Promise<CloseDueResult> {
  const { data, error } = await admin
    .from("fights")
    .select("id, state, starts_at, ends_at")
    .in("state", [...DUE_STATES])
    .order("ends_at", { ascending: true })
    .limit(200);
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fights to close");
  }
  const rows = fightMaintenanceCandidateSchema.array().parse(data);
  const fightIds = await recalculateIds(dueIds(rows, now.getTime()), now);
  await mintDueRecurringFights(admin, now);
  return { checked: rows.length, closed: fightIds.length, fightIds };
}

/** Opening the app: close this user's due fights even if cron has not run. */
export async function closeDueFightsForUser(
  userId: string,
  admin: SupabaseClient = createAdminClient(),
  now: Date = new Date(),
  database: Sql = createDatabaseClient(),
): Promise<CloseDueResult> {
  const [row] = await database`
    select coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', fight.id, 'state', fight.state,
        'starts_at', fight.starts_at, 'ends_at', fight.ends_at
      ) order by fight.ends_at, fight.id)
      from public.fights fight
      join public.fight_members member on member.fight_id = fight.id
      where member.user_id = ${userId} and member.state = 'accepted'
        and fight.state in ('live', 'scheduled', 'awaiting_final_sync')
    ), '[]'::jsonb) as candidates,
    coalesce((
      select jsonb_agg(series.current_fight_id order by current_fight.ends_at, series.id)
      from public.fight_series series
      join public.fights current_fight on current_fight.id = series.current_fight_id
      where series.recurring and series.paused_at is null
        and current_fight.ends_at <= ${now.toISOString()}
        and (series.owner_id = ${userId} or exists (
          select 1 from public.fight_series_members member
          where member.series_id = series.id and member.user_id = ${userId}
            and member.state = 'accepted'
        ))
    ), '[]'::jsonb) as recurring
  `;
  const { candidates, recurring } = userFightMaintenanceSchema.parse(row);
  const fightIds = await recalculateIds(dueIds(candidates, now.getTime()), now, database);
  for (const previousFightId of recurring.slice(0, BATCH)) {
    await mintNextRecurringFight(previousFightId, admin, now);
  }
  return { checked: candidates.length, closed: fightIds.length, fightIds };
}
