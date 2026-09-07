import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { fightSnapshotSchema, type FightSnapshot } from "@/lib/types/fights/fight-snapshot";

/** Read with the caller's RLS policies; the pooler's server role must not broaden visibility. */
export async function readFightSnapshot(
  userId: string,
  timeZone: string,
  database: Sql = createDatabaseClient(),
): Promise<FightSnapshot> {
  return database.begin("read only", async (sql) => {
    await sql`set local role authenticated`;
    await sql`
      select set_config('request.jwt.claim.sub', ${userId}, true),
        set_config('request.jwt.claims', ${JSON.stringify({ sub: userId, role: "authenticated" })}, true)
    `;
    const [row] = await sql<{ snapshot: unknown }[]>`
      with visible_fights as materialized (
        select id, owner_id, name, state, starts_at, ends_at, action_text, series_id
        from public.fights
        where owner_id = ${userId}
          or id in (select fight_id from public.fight_members where user_id = ${userId})
      ), visible_members as materialized (
        select fight_id, user_id, state, current_value, rank, final_value,
          last_synced_at, final_steps_complete
        from public.fight_members
        where fight_id in (select id from visible_fights)
      ), visible_profiles as (
        select user_id, handle, display_name
        from public.profiles
        where user_id in (
          select user_id from visible_members union select owner_id from visible_fights
        )
      ), visible_series as (
        select id, join_code, visibility, recurring
        from public.fight_series
        where id in (select series_id from visible_fights)
      ), chart_bounds as (
        select min((starts_at at time zone ${timeZone})::date) as first_day,
          max(least(
            ((ends_at - interval '1 microsecond') at time zone ${timeZone})::date,
            (starts_at at time zone ${timeZone})::date + 40
          )) as last_day
        from visible_fights
      ), visible_days as (
        select user_id, day, steps
        from public.step_days
        where user_id in (select user_id from visible_members)
          and day between (select first_day from chart_bounds) and (select last_day from chart_bounds)
      )
      select jsonb_build_object(
        'fights', coalesce((select jsonb_agg(to_jsonb(f) order by starts_at, id) from visible_fights f), '[]'::jsonb),
        'members', coalesce((select jsonb_agg(to_jsonb(m) order by fight_id, user_id) from visible_members m), '[]'::jsonb),
        'profiles', coalesce((select jsonb_agg(to_jsonb(p) order by user_id) from visible_profiles p), '[]'::jsonb),
        'series', coalesce((select jsonb_agg(to_jsonb(s) order by id) from visible_series s), '[]'::jsonb),
        'step_days', coalesce((select jsonb_agg(to_jsonb(d) order by day, user_id) from visible_days d), '[]'::jsonb)
      ) as snapshot
    `;
    return fightSnapshotSchema.parse(row.snapshot);
  });
}
