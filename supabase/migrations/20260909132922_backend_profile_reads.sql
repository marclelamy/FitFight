-- Keep client grants until a compatible native build is installable and required.
create role fitfight_backend_reader nologin noinherit nobypassrls;
grant fitfight_backend_reader to postgres;

grant usage on schema public, private, auth to fitfight_backend_reader;
grant execute on function auth.uid() to fitfight_backend_reader;
grant select on public.profiles, public.fights, public.fight_members,
  public.fight_series, public.step_days to fitfight_backend_reader;
grant execute on function private.current_user_can_see_fight(uuid),
  private.current_user_is_roster_member(uuid),
  private.current_user_can_see_series(uuid),
  private.current_user_shares_accepted_fight_day(uuid, date)
  to fitfight_backend_reader;

alter policy profiles_select_visible on public.profiles
  to authenticated, fitfight_backend_reader;
alter policy fights_select_involved on public.fights
  to authenticated, fitfight_backend_reader;
alter policy fight_members_select_self_or_roster_peer on public.fight_members
  to authenticated, fitfight_backend_reader;
alter policy fight_series_select_involved on public.fight_series
  to authenticated, fitfight_backend_reader;
alter policy step_days_select_self_or_fight on public.step_days
  to authenticated, fitfight_backend_reader;
