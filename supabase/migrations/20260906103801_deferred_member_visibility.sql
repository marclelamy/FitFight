-- Deferred members are in the fight but not racing this window.
-- They must still see the fight, the lineup, and current racers' chart days.

create or replace function private.current_user_can_see_fight(_fight_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_members
    where fight_id = _fight_id
      and user_id = auth.uid()
      and state in ('invited', 'accepted', 'deferred')
  );
$$;

create or replace function private.current_user_is_roster_member(_fight_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_members
    where fight_id = _fight_id
      and user_id = auth.uid()
      and state in ('accepted', 'deferred')
  );
$$;

revoke all on function private.current_user_is_roster_member(uuid) from public;
grant execute on function private.current_user_is_roster_member(uuid) to authenticated;

drop policy if exists fight_members_select_self_or_accepted_peer on public.fight_members;
drop policy if exists fight_members_select_self_or_roster_peer on public.fight_members;

create policy fight_members_select_self_or_roster_peer
  on public.fight_members
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.current_user_is_roster_member(fight_id)
  );

create or replace function private.current_user_shares_accepted_fight(_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_members as me
    join public.fight_members as them
      on them.fight_id = me.fight_id
    where me.user_id = auth.uid()
      and them.user_id = _other
      and me.state in ('accepted', 'deferred')
      and them.state = 'accepted'
  );
$$;

create or replace function private.current_user_shares_accepted_fight_day(_other uuid, _day date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_members as me
    join public.fight_members as them
      on them.fight_id = me.fight_id
    join public.fights as fight
      on fight.id = me.fight_id
    where me.user_id = auth.uid()
      and them.user_id = _other
      and me.state in ('accepted', 'deferred')
      and them.state = 'accepted'
      and _day >= (fight.starts_at at time zone fight.time_zone)::date
      and _day <= ((fight.ends_at - interval '1 microsecond') at time zone fight.time_zone)::date
  );
$$;
