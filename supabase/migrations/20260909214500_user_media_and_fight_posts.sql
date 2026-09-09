-- Photos and fight posts. Writes stay on the TypeScript backend.
-- Signed Storage capabilities bypass object policies. No client policy is
-- created for user-media, so clients cannot list, read, or remove objects.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-media',
  'user-media',
  false,
  52428800,
  array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 52428800,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']::text[];

create type public.media_kind as enum ('photo', 'video');
create type public.media_purpose as enum ('profile', 'fight_post');
create type public.media_status as enum ('pending', 'ready', 'rejected');

create table public.media_objects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (user_id) on delete cascade,
  kind public.media_kind not null,
  purpose public.media_purpose not null,
  status public.media_status not null default 'pending',
  bucket_id text not null default 'user-media',
  object_path text not null unique,
  original_filename text not null,
  content_type text not null,
  byte_size bigint not null,
  width integer not null,
  height integer not null,
  duration_ms integer,
  sha256 text not null,
  created_at timestamptz not null default now(),
  committed_at timestamptz,
  constraint media_objects_uuid_v4 check (
    id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  constraint media_objects_filename_len check (char_length(original_filename) between 1 and 200),
  constraint media_objects_content_type check (
    content_type in ('image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime')
  ),
  constraint media_objects_size check (byte_size between 1 and 52428800),
  constraint media_objects_kind_mime check (
    (kind = 'photo' and content_type in ('image/jpeg', 'image/png', 'image/webp') and byte_size <= 8388608)
    or (kind = 'video' and content_type in ('video/mp4', 'video/quicktime'))
  ),
  constraint media_objects_dimensions check (
    width between 1 and 8192 and height between 1 and 8192
  ),
  constraint media_objects_hash check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint media_objects_kind_shape check (
    (kind = 'photo' and duration_ms is null)
    or (kind = 'video' and duration_ms between 1 and 180000)
  ),
  constraint media_objects_path check (
    object_path = owner_id::text || '/' || purpose::text || '/' || id::text
  ),
  constraint media_objects_bucket check (bucket_id = 'user-media')
);

alter table public.profiles
  add column avatar_media_id uuid references public.media_objects (id) on delete set null;

create table public.fight_posts (
  id uuid primary key default gen_random_uuid(),
  fight_id uuid not null references public.fights (id) on delete cascade,
  author_id uuid not null references public.profiles (user_id) on delete cascade,
  body text not null default '',
  created_at timestamptz not null default now(),
  constraint fight_posts_uuid_v4 check (
    id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  constraint fight_posts_body_len check (char_length(body) <= 500)
);

create table public.fight_post_media (
  post_id uuid not null references public.fight_posts (id) on delete cascade,
  media_id uuid not null references public.media_objects (id) on delete restrict,
  sort integer not null default 0,
  primary key (post_id, media_id),
  constraint fight_post_media_sort check (sort between 0 and 3)
);

create unique index fight_post_media_one_post
  on public.fight_post_media (media_id);

create table private.fight_post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.fight_posts (id) on delete cascade,
  reporter_id uuid not null references public.profiles (user_id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  constraint fight_post_reports_reason check (reason in ('spam', 'abuse', 'other')),
  unique (post_id, reporter_id)
);

create table private.feed_blocks (
  blocker_id uuid not null references public.profiles (user_id) on delete cascade,
  blocked_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint feed_blocks_not_self check (blocker_id <> blocked_id)
);

create index media_objects_owner_created_idx
  on public.media_objects (owner_id, created_at desc);
create index fight_posts_fight_created_idx
  on public.fight_posts (fight_id, created_at desc);
create index fight_posts_author_created_idx
  on public.fight_posts (author_id, created_at desc);
create index fight_post_media_post_idx
  on public.fight_post_media (post_id, sort);
create index fight_post_reports_reporter_idx
  on private.fight_post_reports (reporter_id, created_at desc);

revoke all on table public.media_objects from public, anon, authenticated;
revoke all on table public.fight_posts from public, anon, authenticated;
revoke all on table public.fight_post_media from public, anon, authenticated;
revoke all on table private.fight_post_reports from public, anon, authenticated;
revoke all on table private.feed_blocks from public, anon, authenticated;

grant select on public.media_objects to authenticated, fitfight_backend_reader;
grant select on public.fight_posts to authenticated, fitfight_backend_reader;
grant select on public.fight_post_media to authenticated, fitfight_backend_reader;
grant all on table public.media_objects to postgres, service_role;
grant all on table public.fight_posts to postgres, service_role;
grant all on table public.fight_post_media to postgres, service_role;
grant all on table private.fight_post_reports to postgres, service_role;
grant all on table private.feed_blocks to postgres, service_role;

alter table public.media_objects enable row level security;
alter table public.fight_posts enable row level security;
alter table public.fight_post_media enable row level security;
alter table private.fight_post_reports enable row level security;
alter table private.feed_blocks enable row level security;
alter table public.media_objects force row level security;
alter table public.fight_posts force row level security;
alter table public.fight_post_media force row level security;
alter table private.fight_post_reports force row level security;
alter table private.feed_blocks force row level security;

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
          join public.fight_posts as post on post.id = attachment.post_id
          where attachment.media_id = media_objects.id
            and private.current_user_is_roster_member(post.fight_id)
        )
      )
    )
  );

create policy fight_posts_select_roster
  on public.fight_posts
  for select
  to authenticated, fitfight_backend_reader
  using (private.current_user_is_roster_member(fight_id));

create policy fight_post_media_select_roster
  on public.fight_post_media
  for select
  to authenticated, fitfight_backend_reader
  using (
    exists (
      select 1
      from public.fight_posts as post
      where post.id = fight_post_media.post_id
        and private.current_user_is_roster_member(post.fight_id)
    )
  );
