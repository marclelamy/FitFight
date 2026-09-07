begin;
select plan(7);

select has_column('public', 'profiles', 'referral_code', 'Share codes belong to profiles');
select has_table('private', 'referrals', 'Referral relationships are private');
select ok(
  (select bool_and(c.relrowsecurity) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'referrals'),
  'Referral relationships have RLS'
);
select is(has_column_privilege('authenticated', 'public.profiles', 'referral_code', 'UPDATE'),
  false, 'App clients cannot change their referral code');
select is(has_table_privilege('anon', 'private.referrals', 'SELECT,INSERT,UPDATE,DELETE'),
  false, 'Anonymous clients cannot access referral relationships');
select is(has_table_privilege('authenticated', 'private.referrals', 'SELECT,INSERT,UPDATE,DELETE'),
  false, 'App clients cannot access referral relationships directly');
select ok(
  has_table_privilege('service_role', 'private.referrals', 'INSERT'),
  'The backend can record referrals'
);

select * from finish();
rollback;
