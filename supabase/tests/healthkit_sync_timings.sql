begin;
select plan(13);

select has_table('private', 'healthkit_sync_attempts', 'HealthKit timing history is private');
select ok(
  (select relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'healthkit_sync_attempts'),
  'HealthKit timing history has RLS enabled'
);
select is(
  has_table_privilege('anon', 'private.healthkit_sync_attempts', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'anonymous clients cannot read or modify HealthKit timings'
);
select is(
  has_table_privilege('authenticated', 'private.healthkit_sync_attempts', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'authenticated clients cannot read or modify HealthKit timings directly'
);
select ok(
  has_table_privilege('service_role', 'private.healthkit_sync_attempts', 'INSERT'),
  'the backend can insert HealthKit timings'
);

insert into auth.users (
  instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'a1111111-1111-4111-8111-111111111111',
   'authenticated', 'authenticated', 'timing-a@example.com', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a2222222-2222-4222-8222-222222222222',
   'authenticated', 'authenticated', 'timing-b@example.com', '{}', '{}', now(), now());

insert into private.healthkit_sync_attempts (
  user_id, attempt_id, trigger, started_at, outcome, total_ms, stages, app_version, app_build
)
select uid, 'b1111111-1111-4111-8111-111111111111', 'foreground', now(),
  'succeeded', 450.25, '[]', '1.0.0', '42'
from unnest(array[
  'a1111111-1111-4111-8111-111111111111'::uuid,
  'a1111111-1111-4111-8111-111111111111'::uuid,
  'a2222222-2222-4222-8222-222222222222'::uuid
]) as uid
on conflict (user_id, attempt_id) do nothing;

select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a1111111-1111-4111-8111-111111111111'),
  1,
  'duplicate delivery of the same attempt stores one row'
);
select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a2222222-2222-4222-8222-222222222222'),
  1,
  'attempt deduplication is scoped to the authenticated user'
);

insert into private.healthkit_sync_attempts (
  user_id, attempt_id, trigger, started_at, received_at, outcome, total_ms,
  stages, app_version, app_build
)
select 'a1111111-1111-4111-8111-111111111111', gen_random_uuid(), 'manual',
  now(), now() - make_interval(mins => n), 'succeeded', 1, '[]', '1.0.0', '42'
from generate_series(1, 105) as n;

insert into private.healthkit_sync_attempts (
  user_id, attempt_id, trigger, started_at, received_at, outcome, total_ms,
  stages, app_version, app_build
) values
  ('a1111111-1111-4111-8111-111111111111', 'b3333333-3333-4333-8333-333333333333',
   'observer', now() - interval '8 days', now() - interval '8 days',
   'cancelled', 25000, '[]', '1.0.0', '42'),
  ('a2222222-2222-4222-8222-222222222222', 'b4444444-4444-4444-8444-444444444444',
   'observer', now() - interval '8 days', now() - interval '8 days',
   'cancelled', 25000, '[]', '1.0.0', '42');

delete from private.healthkit_sync_attempts
where user_id = 'a1111111-1111-4111-8111-111111111111'
  and (
    received_at < clock_timestamp() - interval '7 days'
    or attempt_id in (
      select attempt_id from private.healthkit_sync_attempts
      where user_id = 'a1111111-1111-4111-8111-111111111111'
      order by received_at desc, attempt_id desc
      offset 100
    )
  );

select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a1111111-1111-4111-8111-111111111111'),
  100,
  'a report retains at most 100 recent attempts for its user'
);
select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where attempt_id = 'b3333333-3333-4333-8333-333333333333'),
  0,
  'a report removes its user attempts older than seven days'
);
select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a2222222-2222-4222-8222-222222222222'),
  2,
  'pruning leaves another user history untouched'
);

delete from private.healthkit_sync_attempts
where user_id = 'a2222222-2222-4222-8222-222222222222'
  and (
    received_at < clock_timestamp() - interval '7 days'
    or attempt_id in (
      select attempt_id from private.healthkit_sync_attempts
      where user_id = 'a2222222-2222-4222-8222-222222222222'
      order by received_at desc, attempt_id desc
      offset 100
    )
  );
select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a2222222-2222-4222-8222-222222222222'),
  1,
  'seven-day pruning also applies below the 100-attempt cap'
);

delete from auth.users where id = 'a1111111-1111-4111-8111-111111111111';
select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a1111111-1111-4111-8111-111111111111'),
  0,
  'account deletion cascades to private timing history'
);
select is(
  (select count(*)::integer from private.healthkit_sync_attempts
    where user_id = 'a2222222-2222-4222-8222-222222222222'),
  1,
  'account deletion preserves another user timing history'
);

select * from finish();
rollback;
