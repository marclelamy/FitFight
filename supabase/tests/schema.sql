begin;
select plan(72);

select has_schema('private', 'private schema exists');
select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'friendships', 'friendships exists');
select has_table('public', 'fights', 'fights exists');
select has_table('public', 'fight_members', 'fight_members exists');
select has_table('public', 'fight_invites', 'fight_invites exists');
select has_table('public', 'fight_series', 'fight_series exists');
select has_table('public', 'fight_series_members', 'fight_series_members exists');
select has_table('private', 'fight_join_attempts', 'join attempts stay private');
select has_table('public', 'data_sources', 'data_sources exists');
select has_table('public', 'step_days', 'step_days exists');
select has_table('private', 'metric_observations', 'observations stay private');
select has_table(
  'private',
  'healthkit_sync_diagnostics',
  'latest HealthKit diagnostics stay private'
);
select has_table(
  'private',
  'healthkit_activity_days',
  'collected Apple Health activity days stay private'
);
select has_table(
  'private',
  'healthkit_workouts',
  'collected Apple Health workouts stay private'
);
select has_table('public', 'feedback_posts', 'feedback posts exist');
select has_table('public', 'feedback_votes', 'feedback votes exist');
select has_table('public', 'feedback_comments', 'feedback comments exist');

select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'profiles'),
  'profiles has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'fights'),
  'fights has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'fight_members'),
  'fight_members has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'data_sources'),
  'data_sources has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'metric_observations'),
  'metric_observations has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'step_days'),
  'step_days has RLS'
);

select is(
  has_table_privilege('anon', 'public.fights', 'SELECT'),
  false,
  'anon cannot read fights'
);
select is(
  has_table_privilege('anon', 'private.metric_observations', 'SELECT'),
  false,
  'anon cannot read observations'
);
select is(
  has_table_privilege('authenticated', 'private.metric_observations', 'SELECT'),
  false,
  'authenticated cannot read observations'
);
select is(
  has_table_privilege('anon', 'private.healthkit_sync_diagnostics', 'SELECT'),
  false,
  'anon cannot read HealthKit diagnostics'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_sync_diagnostics', 'SELECT'),
  false,
  'authenticated clients cannot read HealthKit diagnostics'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_activity_days'),
  'healthkit_activity_days has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_workouts'),
  'healthkit_workouts has RLS'
);
select is(
  has_table_privilege('anon', 'private.healthkit_activity_days', 'SELECT'),
  false,
  'anon cannot read collected Apple Health activity'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_activity_days', 'SELECT'),
  false,
  'authenticated clients cannot read collected Apple Health activity'
);
select is(
  has_table_privilege('anon', 'private.healthkit_workouts', 'SELECT'),
  false,
  'anon cannot read collected Apple Health workouts'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_workouts', 'SELECT'),
  false,
  'authenticated clients cannot read collected Apple Health workouts'
);
select has_table(
  'private',
  'server_error_logs',
  'API failure traces stay private'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'server_error_logs'),
  'server_error_logs has RLS'
);
select is(
  has_table_privilege('anon', 'private.server_error_logs', 'SELECT'),
  false,
  'anon cannot read server error logs'
);
select is(
  has_table_privilege('authenticated', 'private.server_error_logs', 'SELECT'),
  false,
  'authenticated clients cannot read server error logs'
);
select is(
  has_table_privilege('anon', 'private.server_error_logs', 'INSERT'),
  false,
  'anon cannot write server error logs'
);
select is(
  has_table_privilege('authenticated', 'private.server_error_logs', 'INSERT'),
  false,
  'authenticated clients cannot write server error logs'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'feedback_posts'),
  'feedback_posts has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'feedback_votes'),
  'feedback_votes has RLS'
);
select ok(
  (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'feedback_comments'),
  'feedback_comments has RLS'
);
select is(
  has_table_privilege('authenticated', 'public.feedback_posts', 'SELECT'),
  true,
  'signed-in users can read feedback posts'
);
select is(
  has_table_privilege('authenticated', 'public.feedback_posts', 'INSERT'),
  false,
  'clients cannot insert feedback posts'
);
select is(
  has_table_privilege('authenticated', 'public.feedback_comments', 'SELECT'),
  true,
  'signed-in users can read feedback comments'
);
select is(
  has_table_privilege('authenticated', 'public.feedback_comments', 'INSERT'),
  false,
  'clients cannot insert feedback comments'
);
select is(
  has_table_privilege('authenticated', 'public.feedback_votes', 'SELECT'),
  false,
  'clients cannot read feedback votes'
);
select is(
  has_table_privilege('anon', 'public.feedback_posts', 'SELECT'),
  false,
  'anonymous clients cannot read feedback posts'
);
select is(
  has_table_privilege('authenticated', 'public.fights', 'INSERT'),
  false,
  'clients cannot insert fights directly'
);
select is(
  has_table_privilege('authenticated', 'public.fights', 'UPDATE'),
  false,
  'clients cannot update server-owned fights'
);
select is(
  has_table_privilege('authenticated', 'public.fight_members', 'UPDATE'),
  false,
  'clients cannot update membership or scores directly'
);
select is(
  has_table_privilege('authenticated', 'public.data_sources', 'INSERT'),
  false,
  'clients cannot insert data sources directly'
);
select is(
  has_column_privilege('authenticated', 'public.profiles', 'handle', 'UPDATE'),
  true,
  'users can set their handle'
);
select is(
  has_table_privilege('authenticated', 'private.metric_observations', 'INSERT'),
  false,
  'authenticated still cannot write private observations'
);
select is(
  has_column_privilege('authenticated', 'public.fight_invites', 'token_hash', 'SELECT'),
  false,
  'clients cannot read invite token hashes'
);
select is(
  has_table_privilege('authenticated', 'public.fight_series', 'INSERT'),
  false,
  'clients cannot insert fight series'
);
select is(
  has_table_privilege('authenticated', 'private.fight_join_attempts', 'SELECT'),
  false,
  'authenticated cannot read join attempts'
);
select is(
  has_table_privilege('anon', 'public.fight_series', 'SELECT'),
  false,
  'anon cannot read fight series'
);
select is(
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
  true,
  'users can update their display name'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fight_members'
      and column_name = 'last_synced_at'
  ),
  'fight_members stores last sync time'
);
select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fight_members'
      and column_name = 'final_steps_complete'
  ),
  'fight_members exposes Fight-scoped final Steps completeness'
);
select is(
  (
    select column_default
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fight_members'
      and column_name = 'final_steps_complete'
  ),
  'false',
  'final Steps completeness defaults to false'
);

select ok(
  exists (select 1 from pg_constraint where conname = 'fights_metric_steps_only'),
  'fights are locked to steps'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'fights_series_starts_at_idx'
  ),
  'recurring fights are unique per series window'
);
select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fight_series'
      and column_name = 'join_code'
  ),
  'NO',
  'every fight series has a join code'
);
select ok(
  exists (select 1 from pg_constraint where conname = 'metric_observations_metric_steps_only'),
  'observations are locked to steps'
);

select ok(
  to_regprocedure('public.delete_own_account()') is null,
  'account deletion is not exposed as an RPC'
);
select is(
  has_table_privilege('anon', 'private.provider_uploads', 'SELECT'),
  false,
  'anon cannot read provider uploads'
);
select is(
  has_table_privilege('authenticated', 'private.provider_uploads', 'SELECT'),
  false,
  'authenticated clients cannot read provider uploads'
);
select is(
  (select file_size_limit from storage.buckets where id = 'provider-inbox'),
  536870912::bigint,
  'provider inbox accepts large HealthKit archives'
);

select * from finish();
rollback;
