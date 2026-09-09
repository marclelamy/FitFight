-- Apply in a later release, after the backend-only app is installable and required.
revoke all on public.profiles, public.friendships, public.fights,
  public.data_sources, public.fight_members, public.fight_invites,
  public.step_days, public.metric_days, public.fight_series, public.fight_series_members,
  public.feedback_posts, public.feedback_votes, public.feedback_comments,
  public.media_objects, public.fight_posts, public.fight_post_media,
  public.fight_post_tags, public.fight_post_reactions, public.fight_post_comments
  from public, anon, authenticated;

-- Table revocation does not remove privileges granted separately on columns.
revoke all (handle, handle_set_at, display_name, avatar_path, time_zone, avatar_media_id)
  on public.profiles from public, anon, authenticated;
revoke all (state) on public.friendships from public, anon, authenticated;
revoke all (id, fight_id, invited_user_id, expires_at, revoked_at, accepted_at)
  on public.fight_invites from public, anon, authenticated;

revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

-- Global defaults also apply within public; schema-level revocation cannot undo them.
alter default privileges for role postgres
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres
  revoke all on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from public, anon, authenticated;

alter policy profiles_select_visible on public.profiles to fitfight_backend_reader;
alter policy fights_select_involved on public.fights to fitfight_backend_reader;
alter policy fight_members_select_self_or_roster_peer on public.fight_members to fitfight_backend_reader;
alter policy fight_series_select_involved on public.fight_series to fitfight_backend_reader;
alter policy step_days_select_self_or_fight on public.step_days to fitfight_backend_reader;
alter policy media_objects_select_owner_or_shared on public.media_objects to fitfight_backend_reader;
alter policy fight_posts_select_roster on public.fight_posts to fitfight_backend_reader;
alter policy fight_post_media_select_roster on public.fight_post_media to fitfight_backend_reader;
alter policy fight_post_tags_select_visible on public.fight_post_tags to fitfight_backend_reader;
alter policy fight_post_reactions_select_visible on public.fight_post_reactions to fitfight_backend_reader;
alter policy fight_post_comments_select_visible on public.fight_post_comments to fitfight_backend_reader;
