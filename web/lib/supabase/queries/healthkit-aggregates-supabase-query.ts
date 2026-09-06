import { createHash } from "node:crypto";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { scoreFight } from "@/lib/scoring/score-fight";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  healthKitAggregateFightSchema,
  healthKitAggregateMemberSchema,
  healthKitAggregateSourceSchema,
} from "@/lib/types/healthkit/healthkit-aggregate-database";
import type {
  HealthKitAggregateSync,
  HealthKitAggregateSyncResponse,
} from "@/lib/types/healthkit/healthkit-aggregate";

export async function syncHealthKitAggregates(
  userId: string,
  input: HealthKitAggregateSync,
  database: Sql = createDatabaseClient(),
): Promise<HealthKitAggregateSyncResponse> {
  return database.begin("read write", async (sql) => {
    const [sourceRow] = await sql`
      insert into public.data_sources (
        user_id, provider, source_label, connection_route, capabilities,
        status, consent_version, connected_at, last_success_at, complete_through
      ) values (
        ${userId}, 'apple_health', 'Apple Health', 'healthkit', array['steps']::text[],
        'healthy', 1, now(), now(), ${input.complete_through}
      )
      on conflict (user_id, provider, connection_route) do update
      set status = 'healthy', revoked_at = null, last_success_at = now(),
        complete_through = greatest(
          coalesce(public.data_sources.complete_through, excluded.complete_through),
          excluded.complete_through
        ),
        last_error_code = null
      returning id, complete_through::text as complete_through,
        clock_timestamp()::text as server_now
    `;
    if (!sourceRow) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not save Apple Health source");
    }
    const source = healthKitAggregateSourceSchema.parse(sourceRow);
    if (Date.parse(input.complete_through) > Date.parse(source.server_now)) {
      throw new ApiError(
        400,
        ERROR_CODES.validation,
        "complete_through cannot be in the future",
      );
    }
    if (Date.parse(source.complete_through) > Date.parse(input.complete_through)) {
      throw new ApiError(409, ERROR_CODES.conflict, "Sync is older than current Apple Health data");
    }

    const fightIds = input.fight_aggregates.map((aggregate) => aggregate.fight_id);
    const fights = healthKitAggregateFightSchema.array().parse(await sql`
      select fight.id as fight_id, fight.starts_at::text as starts_at,
        fight.ends_at::text as ends_at,
        fight.outcome_rule::text as outcome_rule,
        fight.stake_minor,
        fight.default_goal_value::text as default_goal_value
      from public.fights as fight
      join public.fight_members as member on member.fight_id = fight.id
      where member.user_id = ${userId}
        and member.state = 'accepted'
        and fight.state in ('live', 'awaiting_final_sync')
      order by fight.id
      for update of fight, member
    `);
    const submittedFightIds = new Set(fightIds);
    if (fights.length !== submittedFightIds.size
      || fights.some((fight) => !submittedFightIds.has(fight.fight_id))) {
      throw new ApiError(
        400,
        ERROR_CODES.validation,
        "Fight aggregate set does not match sync context",
      );
    }
    const fightsById = new Map(fights.map((fight) => [fight.fight_id, fight]));
    const aggregateFights = input.fight_aggregates.map((aggregate) => {
      const fight = fightsById.get(aggregate.fight_id);
      const expectedCutoff = fight
        ? Math.min(Date.parse(input.complete_through), Date.parse(fight.ends_at))
        : Number.NaN;
      if (!fight
        || Date.parse(aggregate.starts_at) !== Date.parse(fight.starts_at)
        || Date.parse(aggregate.ends_at) !== Date.parse(fight.ends_at)
        || Date.parse(aggregate.cutoff_at) !== expectedCutoff) {
        throw new ApiError(
          400,
          ERROR_CODES.validation,
          "Fight aggregate does not match sync context",
        );
      }
      return {
        fight_id: aggregate.fight_id,
        cutoff_at: aggregate.cutoff_at,
        value: aggregate.steps,
        // A later read can return to an earlier value at the same Fight-end cutoff.
        input_hash: createHash("sha256").update(JSON.stringify({
          ...aggregate, complete_through: input.complete_through,
        })).digest("hex"),
        final_steps_complete: Date.parse(input.complete_through) >= Date.parse(fight.ends_at),
      };
    });

    for (const day of input.merged_days) {
      const overlapsSubmittedFight = fights.some((fight) =>
        Date.parse(day.starts_at) < Math.min(
          Date.parse(fight.ends_at),
          Date.parse(input.complete_through),
        )
        && Date.parse(day.ends_at) > Date.parse(fight.starts_at)
      );
      if (!overlapsSubmittedFight) {
        throw new ApiError(
          400,
          ERROR_CODES.validation,
          "Merged day does not overlap a submitted Fight",
        );
      }
    }

    if (input.merged_days.length > 0) {
      const dayRows = input.merged_days.map((day) => ({
        user_id: userId,
        source_id: source.id,
        metric: "steps",
        day: day.day,
        value: day.steps,
        unit: "steps",
        input_hash: createHash("sha256").update(JSON.stringify({
          time_zone: input.time_zone,
          ...day,
        })).digest("hex"),
        normalization_version: 1,
        calculation_version: 1,
      }));
      await sql`
        insert into public.metric_days ${sql(
          dayRows,
          "user_id",
          "source_id",
          "metric",
          "day",
          "value",
          "unit",
          "input_hash",
          "normalization_version",
          "calculation_version",
        )}
        on conflict (user_id, source_id, metric, day) do update
        set value = excluded.value,
          input_hash = excluded.input_hash,
          normalization_version = excluded.normalization_version,
          calculation_version = excluded.calculation_version,
          finalized_at = null,
          updated_at = now()
      `;
      await sql`
        insert into public.step_days (user_id, day, steps, updated_at)
        select user_id, day, value::integer, updated_at
        from public.metric_days
        where user_id = ${userId}
          and source_id = ${source.id}
          and metric = 'steps'
          and day = any(${sql.array(input.merged_days.map((day) => day.day))}::date[])
        on conflict (user_id, day) do update
        set steps = excluded.steps, updated_at = excluded.updated_at
      `;
    }

    if (aggregateFights.length > 0) {
      await sql`
        insert into private.fight_score_snapshots (
          fight_id, user_id, source_id, cutoff_at, value,
          input_hash, calculation_version, is_final, created_at
        )
        select aggregate.fight_id, ${userId}, ${source.id}, aggregate.cutoff_at,
          aggregate.value, aggregate.input_hash, 1, false, clock_timestamp()
        from jsonb_to_recordset(${sql.json(aggregateFights)}::jsonb) as aggregate (
          fight_id uuid, cutoff_at timestamptz, value numeric, input_hash text
        )
        where true
        on conflict (fight_id, user_id, cutoff_at, input_hash) do nothing
      `;

      // A separate statement sees the inserted snapshots, including replayed/corrected totals.
      const updatedMembers = healthKitAggregateFightSchema.pick({ fight_id: true }).array().parse(await sql`
        with latest as (
          select distinct on (fight_id) fight_id, value
          from private.fight_score_snapshots
          where fight_id = any(${sql.array(fightIds)}::uuid[])
            and user_id = ${userId}
            and source_id = ${source.id}
          order by fight_id, cutoff_at desc, created_at desc, id desc
        )
        update public.fight_members as member
        set current_value = latest.value,
          selected_source_id = ${source.id},
          source_label = 'Apple Health',
          freshness = 'recent',
          last_synced_at = now(),
          final_steps_complete = member.final_steps_complete or aggregate.final_steps_complete,
          input_revision = case
            when member.current_value is distinct from latest.value
              or member.selected_source_id is distinct from ${source.id}
              or member.source_label is distinct from 'Apple Health'
              or member.freshness is distinct from 'recent'
            then coalesce(member.input_revision, 0) + 1
            else member.input_revision
          end
        from latest
        join jsonb_to_recordset(${sql.json(aggregateFights)}::jsonb) as aggregate (
          fight_id uuid, final_steps_complete boolean
        ) on aggregate.fight_id = latest.fight_id
        where member.fight_id = latest.fight_id
          and member.user_id = ${userId}
          and member.state = 'accepted'
        returning member.fight_id
      `);
      if (updatedMembers.length !== fights.length) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not save Fight aggregate");
      }
      const members = healthKitAggregateMemberSchema.array().parse(await sql`
        select fight_id, user_id, current_value::text, final_value::text, personal_target::text
        from public.fight_members
        where fight_id = any(${sql.array(fightIds)}::uuid[]) and state = 'accepted'
        order by fight_id, user_id
        for update
      `);
      const scores = fights.flatMap((fight) => scoreFight({
        outcomeRule: fight.outcome_rule,
        stakeMinor: fight.stake_minor,
        defaultGoalValue: fight.default_goal_value,
        members: members.filter((member) => member.fight_id === fight.fight_id)
          .map((member) => ({
            userId: member.user_id,
            value: member.current_value ?? member.final_value ?? 0,
            personalTarget: member.personal_target,
          })),
      }).map((score) => ({
        fight_id: fight.fight_id,
        user_id: score.userId,
        rank: score.rank,
        outcome_minor: score.outcomeMinor,
      })));
      if (scores.length > 0) {
        await sql`
          update public.fight_members as member
          set rank = score.rank, outcome_minor = score.outcome_minor
          from jsonb_to_recordset(${sql.json(scores)}::jsonb) as score (
            fight_id uuid, user_id uuid, rank integer, outcome_minor integer
          )
          where member.fight_id = score.fight_id and member.user_id = score.user_id
        `;
      }
    }

    return {
      complete_through: input.complete_through,
      synced_days: input.merged_days.length,
      synced_fights: input.fight_aggregates.length,
    };
  });
}
