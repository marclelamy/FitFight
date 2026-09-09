import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";

export async function verifyBackendReadiness(
  database: Sql = createDatabaseClient(),
): Promise<void> {
  await database`
    select 1 / migration.applied::integer as migration_ready,
      profile.deleted_at, profile.handle_set_at, profile.referral_code,
      fight.action_text, member.current_value,
      source.complete_through, day.calculation_version, snapshot.cutoff_at,
      apple_token.encrypted_refresh_token
    from (
      select count(*) as applied
      from supabase_migrations.schema_migrations
      where version = '20260909132922'
    ) as migration
    left join public.profiles as profile on false
    left join public.fights as fight on false
    left join public.fight_members as member on false
    left join public.data_sources as source on false
    left join public.metric_days as day on false
    left join private.fight_score_snapshots as snapshot on false
    left join private.apple_sign_in_tokens as apple_token on false
  `;

  await database.begin("read only", async (sql) => {
    await sql`set local role fitfight_backend_reader`;
    await sql`select user_id from public.profiles limit 0`;
  });

  const { error } = await createAdminClient().auth.admin.listUsers({ page: 1, perPage: 1 });
  if (error) {
    throw new ApiError(503, ERROR_CODES.config, "Supabase server key is not ready");
  }
}
