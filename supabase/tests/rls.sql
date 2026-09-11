begin;
select plan(36);

create function pg_temp.make_user(uid uuid, email text)
returns void
language plpgsql
as $$
begin
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    uid,
    'authenticated',
    'authenticated',
    email,
    extensions.crypt('password123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    uid,
    uid,
    jsonb_build_object('sub', uid::text, 'email', email),
    'email',
    uid::text,
    now(),
    now(),
    now()
  );
end;
$$;

select pg_temp.make_user('11111111-1111-4111-8111-111111111111', 'maya@example.com');
select pg_temp.make_user('22222222-2222-4222-8222-222222222222', 'leo@example.com');
select pg_temp.make_user('33333333-3333-4333-8333-333333333333', 'ivy@example.com');
select pg_temp.make_user('55555555-5555-4555-8555-555555555555', 'nina@example.com');

insert into public.fights (
  id, owner_id, name, state, starts_at, ends_at, time_zone,
  outcome_rule, goal_policy
) values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111',
  'Steps',
  'live',
  now(),
  now() + interval '7 days',
  'America/New_York',
  'highest_total',
  'shared'
);

insert into public.fight_members (fight_id, user_id, state) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'accepted'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'accepted'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-3333-4333-8333-333333333333', 'invited'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '55555555-5555-4555-8555-555555555555', 'deferred');

create function pg_temp.as_user(uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', uid::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select lives_ok(
  $$ select * from public.fight_members $$,
  'accepted member can read fight_members without recursion'
);

select is(
  (select count(*)::integer from public.fight_members),
  4,
  'accepted member sees the whole lineup'
);

select lives_ok(
  $$ insert into public.friendships (requester_id, addressee_id, state)
     values (
       '11111111-1111-4111-8111-111111111111',
       '22222222-2222-4222-8222-222222222222',
       'accepted'
     ) $$,
  'requester can add a friend without a pending request'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.fight_members),
  1,
  'invitee sees only their own membership'
);

select is(
  (select count(*)::integer from public.fights),
  1,
  'invitee can still see the fight'
);

reset role;
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
set local role authenticated;

select lives_ok(
  $$ insert into public.friendships (requester_id, addressee_id, state)
     values (
       '11111111-1111-4111-8111-111111111111',
       '33333333-3333-4333-8333-333333333333',
       'pending'
     ) $$,
  'requester can still insert a pending friendship'
);

select throws_ok(
  $$ insert into public.fights (
       id, owner_id, name, state, starts_at, ends_at, time_zone,
       outcome_rule, goal_policy
     ) values (
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '11111111-1111-4111-8111-111111111111',
       'Phone fight',
       'live',
       now(),
       now() + interval '3 days',
       'America/New_York',
       'highest_total',
       'shared'
     ) $$,
  '42501',
  'permission denied for table fights',
  'owner cannot create a fight outside server commands'
);

select throws_ok(
  $$ insert into public.fight_members (fight_id, user_id, state)
     values (
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '11111111-1111-4111-8111-111111111111',
       'accepted'
     ) $$,
  '42501',
  'permission denied for table fight_members',
  'owner cannot self-accept outside server commands'
);

select throws_ok(
  $$ insert into public.fight_members (fight_id, user_id, state)
     values (
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '22222222-2222-4222-8222-222222222222',
       'invited'
     ) $$,
  '42501',
  'permission denied for table fight_members',
  'owner cannot write another membership'
);

select throws_ok(
  $$ insert into public.fight_members (fight_id, user_id, state) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '44444444-4444-4444-8444-444444444444', 'accepted') $$,
  '42501',
  'permission denied for table fight_members',
  'owner cannot forge another person consent to health sharing'
);

select throws_ok(
  $$ update public.fight_members set current_value = 999999, final_value = 999999, rank = 1, final_steps_complete = true where user_id = '11111111-1111-4111-8111-111111111111' $$,
  '42501',
  'permission denied for table fight_members',
  'a member cannot forge their scores, rank, or completeness'
);

select throws_ok(
  $$ update public.fight_members set fight_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where user_id = '11111111-1111-4111-8111-111111111111' $$,
  '42501',
  'permission denied for table fight_members',
  'a member cannot move their consent to another fight'
);

select throws_ok(
  $$ update public.fights set starts_at = now() - interval '1 year', ends_at = now() + interval '1 year' where owner_id = '11111111-1111-4111-8111-111111111111' $$,
  '42501',
  'permission denied for table fights',
  'owner cannot widen a fight to expose historical health days'
);

select throws_ok(
  $$ update public.fights set state = 'final' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501',
  'permission denied for table fights',
  'owner cannot bypass server finalization'
);

select throws_ok(
  $$ update public.data_sources set complete_through = now() + interval '1 year' where user_id = '11111111-1111-4111-8111-111111111111' $$,
  '42501',
  'permission denied for table data_sources',
  'a user cannot forge source completeness'
);

select throws_ok(
  $$ insert into public.step_days (user_id, day, steps)
     values (
       '11111111-1111-4111-8111-111111111111',
       current_date,
       8000
     ) $$,
  '42501',
  'permission denied for table step_days',
  'clients cannot write server-owned step totals'
);

reset role;
insert into public.step_days (user_id, day, steps)
values (
  '11111111-1111-4111-8111-111111111111',
  current_date,
  8000
);
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select throws_ok(
  $$ insert into public.fights (
       id, owner_id, name, state, starts_at, ends_at, time_zone,
       outcome_rule, goal_policy
     ) values (
       'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
       '11111111-1111-4111-8111-111111111111',
       'Stolen',
       'live',
       now(),
       now() + interval '3 days',
       'America/New_York',
       'highest_total',
       'shared'
     ) $$,
  '42501',
  'permission denied for table fights',
  'cannot create a fight as someone else'
);

select is(
  (select steps from public.step_days
    where user_id = '11111111-1111-4111-8111-111111111111'
      and day = current_date),
  8000,
  'accepted fight peer can read the other person steps'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.step_days),
  0,
  'invitee who has not accepted cannot read peer steps'
);

select throws_ok(
  $$ update public.fight_members
        set state = 'accepted',
            accepted_at = now()
      where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        and user_id = '33333333-3333-4333-8333-333333333333' $$,
  '42501',
  'permission denied for table fight_members',
  'invitee cannot bypass the acceptance command'
);

reset role;
insert into public.feedback_posts (id, author_id, kind, title, body)
values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '11111111-1111-4111-8111-111111111111',
  'bug',
  'Steps chart is blank',
  'The daily Steps chart on a live fight stays empty after a successful sync.'
);

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
set local role authenticated;

select is(
  (select count(*)::integer from public.feedback_posts),
  1,
  'signed-in users can read the public request board'
);

select throws_ok(
  $$ insert into public.feedback_posts (author_id, kind, title, body)
     values (
       '22222222-2222-4222-8222-222222222222',
       'feature',
       'Show weekly totals',
       'A weekly Steps total on You would make it easier to plan a fight.'
     ) $$,
  '42501',
  'permission denied for table feedback_posts',
  'clients cannot insert feedback posts'
);

select throws_ok(
  $$ insert into public.feedback_comments (post_id, author_id, body)
     values (
       'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
       '22222222-2222-4222-8222-222222222222',
       'I see this too'
     ) $$,
  '42501',
  'permission denied for table feedback_comments',
  'clients cannot insert feedback comments'
);

select throws_ok(
  $$ insert into public.feedback_votes (post_id, user_id)
     values (
       'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
       '22222222-2222-4222-8222-222222222222'
     ) $$,
  '42501',
  'permission denied for table feedback_votes',
  'clients cannot insert feedback votes'
);

reset role;
select pg_temp.as_user('44444444-4444-4444-8444-444444444444');
set local role authenticated;

select throws_ok(
  $$ insert into public.fight_members (fight_id, user_id, state)
     values (
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       '44444444-4444-4444-8444-444444444444',
       'accepted'
     ) $$,
  '42501',
  'permission denied for table fight_members',
  'strangers cannot client-insert themselves onto a fight'
);

reset role;
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
set local role authenticated;

select is(
  (select count(*)::integer from public.fight_series),
  0,
  'unrelated users cannot read a series they are not in'
);

reset role;
select pg_temp.as_user('55555555-5555-4555-8555-555555555555');
set local role authenticated;

select is(
  (select count(*)::integer from public.fights),
  1,
  'deferred member can still see the fight'
);

select is(
  (select count(*)::integer from public.fight_members),
  4,
  'deferred member sees the whole lineup'
);

select is(
  (select steps from public.step_days
    where user_id = '11111111-1111-4111-8111-111111111111'
      and day = current_date),
  8000,
  'deferred member can read current racers chart days'
);

reset role;
insert into public.data_sources (
  id, user_id, provider, source_label, connection_route
) values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '11111111-1111-4111-8111-111111111111',
  'apple_health',
  'Apple Health',
  'healthkit'
);

update public.fights
set state = 'awaiting_final_sync'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

update public.fight_members
set current_value = 12_000
where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and user_id = '11111111-1111-4111-8111-111111111111';

select ok(
  (select current_value::integer from public.fight_members
    where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and user_id = '11111111-1111-4111-8111-111111111111') = 12000,
  'awaiting_final_sync still accepts score updates before the fight finalizes'
);

update public.fights
set state = 'final'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select isnt(
  (select finalized_at from public.fight_members
    where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and user_id = '11111111-1111-4111-8111-111111111111'),
  null,
  'moving a fight to final freezes accepted member scores together'
);

update public.fight_members
set current_value = 1
where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and user_id = '11111111-1111-4111-8111-111111111111';

select ok(
  (select current_value::integer from public.fight_members
    where fight_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and user_id = '11111111-1111-4111-8111-111111111111') = 12000,
  'finalized member scores ignore later aggregation writes'
);

update public.fights
set state = 'live'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select state::text from public.fights
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'final',
  'a final fight cannot return to live'
);

insert into public.fights (
  id, owner_id, name, state, starts_at, ends_at, time_zone,
  outcome_rule, goal_policy
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111',
  'Phone fight',
  'final',
  now(),
  now() + interval '3 days',
  'America/New_York',
  'highest_total',
  'shared'
);

insert into public.fight_members (
  fight_id, user_id, state, current_value, finalized_at, selected_source_id
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '33333333-3333-4333-8333-333333333333',
  'invited',
  42,
  now(),
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
);

select ok(
  (select current_value is null
      and finalized_at is null
      and selected_source_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
   from public.fight_members
    where fight_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and user_id = '33333333-3333-4333-8333-333333333333'),
  'insert strips scores even for the database role and keeps the selected source'
);

insert into public.metric_days (
  user_id, source_id, metric, day, value, unit, input_hash,
  normalization_version, calculation_version, finalized_at
) values (
  '11111111-1111-4111-8111-111111111111',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'steps',
  current_date,
  9000,
  'steps',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  1,
  1,
  now()
);

update public.metric_days
set value = 1
where user_id = '11111111-1111-4111-8111-111111111111'
  and day = current_date;

select is(
  (select value::integer from public.metric_days
    where user_id = '11111111-1111-4111-8111-111111111111'
      and day = current_date),
  9000,
  'finalized metric days ignore later aggregation writes'
);

update public.step_days
set steps = 1
where user_id = '11111111-1111-4111-8111-111111111111'
  and day = current_date;

select is(
  (select steps from public.step_days
    where user_id = '11111111-1111-4111-8111-111111111111'
      and day = current_date),
  9000,
  'frozen step days pin to the finalized metric day total'
);

select * from finish();
rollback;
