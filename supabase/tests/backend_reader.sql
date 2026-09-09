begin;
select plan(10);

select ok(
  (select not rolcanlogin and not rolbypassrls and not rolinherit
   from pg_roles where rolname = 'fitfight_backend_reader'),
  'backend reader has no login, RLS bypass, or inherited client writes'
);
select ok(pg_has_role('postgres', 'fitfight_backend_reader', 'MEMBER'), 'server can assume reader');
select ok(not pg_has_role('authenticated', 'fitfight_backend_reader', 'MEMBER'), 'users cannot assume reader');
select ok(not pg_has_role('anon', 'fitfight_backend_reader', 'MEMBER'), 'anonymous callers cannot assume reader');
select ok(not pg_has_role('authenticator', 'fitfight_backend_reader', 'MEMBER'), 'Data API cannot assume reader');
select ok(has_table_privilege('fitfight_backend_reader', 'public.profiles', 'SELECT'), 'backend can read profiles');
select ok(not has_table_privilege('fitfight_backend_reader', 'public.profiles', 'UPDATE'), 'reader cannot update profiles');
select ok(not has_table_privilege('fitfight_backend_reader', 'public.fight_members', 'INSERT'), 'reader cannot create memberships');
select ok(not has_table_privilege('fitfight_backend_reader', 'private.referrals', 'SELECT'), 'reader cannot read private referrals');
select ok(not has_table_privilege('fitfight_backend_reader', 'private.healthkit_sync_attempts', 'SELECT'), 'reader cannot read private Health diagnostics');

select * from finish();
rollback;
