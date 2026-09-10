-- Main-feed posts, tags, emoji reactions, and nested comments.
-- Writes stay on the TypeScript backend.

alter table public.fight_posts
  add column audience text not null default 'fight';

alter table public.fight_posts
  alter column fight_id drop not null;

alter table public.fight_posts
  add constraint fight_posts_audience_check
  check (audience in ('fight', 'main'));

alter table public.fight_posts
  add constraint fight_posts_audience_shape
  check (
    (audience = 'fight' and fight_id is not null)
    or (audience = 'main' and fight_id is null)
  );

drop index if exists public.fight_post_media_one_post;

create table public.fight_post_tags (
  post_id uuid not null references public.fight_posts (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.fight_post_reactions (
  post_id uuid not null references public.fight_posts (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id),
  constraint fight_post_reactions_emoji_len check (char_length(emoji) between 1 and 16),
  constraint fight_post_reactions_emoji_print check (emoji !~ '[[:cntrl:]]')
);

create table public.fight_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.fight_posts (id) on delete cascade,
  parent_id uuid references public.fight_post_comments (id) on delete cascade,
  author_id uuid not null references public.profiles (user_id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint fight_post_comments_uuid_v4 check (
    id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  constraint fight_post_comments_body_len check (char_length(body) between 1 and 500)
);

create table private.fight_post_comment_reports (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.fight_post_comments (id) on delete cascade,
  reporter_id uuid not null references public.profiles (user_id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  constraint fight_post_comment_reports_reason check (reason in ('spam', 'abuse', 'other')),
  unique (comment_id, reporter_id)
);

create index fight_posts_audience_created_idx
  on public.fight_posts (audience, created_at desc, id desc);
create index fight_post_tags_user_idx
  on public.fight_post_tags (user_id, created_at desc);
create index fight_post_reactions_emoji_idx
  on public.fight_post_reactions (post_id, emoji);
create index fight_post_comments_post_created_idx
  on public.fight_post_comments (post_id, created_at, id);
create index fight_post_comments_parent_idx
  on public.fight_post_comments (parent_id, created_at);
create index fight_post_comment_reports_reporter_idx
  on private.fight_post_comment_reports (reporter_id, created_at desc);

create function private.fight_post_comment_same_post()
returns trigger
language plpgsql
as $$
begin
  if new.parent_id is null then
    return new;
  end if;
  if not exists (
    select 1
    from public.fight_post_comments as parent
    where parent.id = new.parent_id
      and parent.post_id = new.post_id
  ) then
    raise exception 'parent comment must belong to the same post';
  end if;
  return new;
end;
$$;

create trigger fight_post_comments_same_post
  before insert or update of parent_id, post_id
  on public.fight_post_comments
  for each row
  execute function private.fight_post_comment_same_post();

create function private.current_user_can_see_fight_post(_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.fight_posts as post
    where post.id = _post_id
      and (
        (
          post.audience = 'main'
          and (
            post.author_id = (select auth.uid())
            or exists (
              select 1
              from public.fight_members as me
              join public.fight_members as them
                on them.fight_id = me.fight_id
              where me.user_id = (select auth.uid())
                and them.user_id = post.author_id
                and me.state in ('accepted', 'deferred')
                and them.state in ('accepted', 'deferred')
            )
          )
        )
        or (
          post.audience = 'fight'
          and (
            private.current_user_is_roster_member(post.fight_id)
            or exists (
              select 1
              from public.fights as posted
              join public.fights as sibling
                on sibling.series_id = posted.series_id
              where posted.id = post.fight_id
                and posted.series_id is not null
                and private.current_user_is_roster_member(sibling.id)
            )
          )
        )
      )
  );
$$;

revoke all on function private.fight_post_comment_same_post() from public;
revoke all on function private.current_user_can_see_fight_post(uuid) from public;
grant execute on function private.current_user_can_see_fight_post(uuid)
  to authenticated, fitfight_backend_reader;

revoke all on table public.fight_post_tags from public, anon, authenticated;
revoke all on table public.fight_post_reactions from public, anon, authenticated;
revoke all on table public.fight_post_comments from public, anon, authenticated;
revoke all on table private.fight_post_comment_reports from public, anon, authenticated;

grant select on public.fight_post_tags to authenticated, fitfight_backend_reader;
grant select on public.fight_post_reactions to authenticated, fitfight_backend_reader;
grant select on public.fight_post_comments to authenticated, fitfight_backend_reader;
grant all on table public.fight_post_tags to postgres, service_role;
grant all on table public.fight_post_reactions to postgres, service_role;
grant all on table public.fight_post_comments to postgres, service_role;
grant all on table private.fight_post_comment_reports to postgres, service_role;

alter table public.fight_post_tags enable row level security;
alter table public.fight_post_reactions enable row level security;
alter table public.fight_post_comments enable row level security;
alter table private.fight_post_comment_reports enable row level security;
alter table public.fight_post_tags force row level security;
alter table public.fight_post_reactions force row level security;
alter table public.fight_post_comments force row level security;
alter table private.fight_post_comment_reports force row level security;

drop policy if exists fight_posts_select_roster on public.fight_posts;
create policy fight_posts_select_roster
  on public.fight_posts
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_can_see_fight_post(id));

drop policy if exists fight_post_media_select_roster on public.fight_post_media;
create policy fight_post_media_select_roster
  on public.fight_post_media
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_can_see_fight_post(post_id));

drop policy if exists media_objects_select_owner_or_shared on public.media_objects;
create policy media_objects_select_owner_or_shared
  on public.media_objects
  for select
  to authenticated, fitfight_backend_reader
  using (
    owner_id = (select auth.uid())
    or (
      status = 'ready'
      and (
        exists (
          select 1
          from public.profiles as profile
          where profile.avatar_media_id = media_objects.id
            and private.current_user_shares_accepted_fight(profile.user_id)
        )
        or exists (
          select 1
          from public.fight_post_media as attachment
          where attachment.media_id = media_objects.id
            and private.current_user_can_see_fight_post(attachment.post_id)
        )
      )
    )
  );

create policy fight_post_tags_select_visible
  on public.fight_post_tags
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_can_see_fight_post(post_id));

create policy fight_post_reactions_select_visible
  on public.fight_post_reactions
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_can_see_fight_post(post_id));

create policy fight_post_comments_select_visible
  on public.fight_post_comments
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_can_see_fight_post(post_id));
