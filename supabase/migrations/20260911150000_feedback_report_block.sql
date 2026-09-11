-- User report and block for the public Bugs & requests board.

create table private.feedback_post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.feedback_posts (id) on delete cascade,
  reporter_id uuid not null references public.profiles (user_id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  constraint feedback_post_reports_reason check (reason in ('spam', 'abuse', 'other')),
  unique (post_id, reporter_id)
);

create table private.feedback_blocks (
  blocker_id uuid not null references public.profiles (user_id) on delete cascade,
  blocked_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint feedback_blocks_not_self check (blocker_id <> blocked_id)
);

create index feedback_post_reports_reporter_idx
  on private.feedback_post_reports (reporter_id, created_at desc);

revoke all on table private.feedback_post_reports from public, anon, authenticated;
revoke all on table private.feedback_blocks from public, anon, authenticated;
grant all on table private.feedback_post_reports to postgres, service_role;
grant all on table private.feedback_blocks to postgres, service_role;

alter table private.feedback_post_reports enable row level security;
alter table private.feedback_blocks enable row level security;
alter table private.feedback_post_reports force row level security;
alter table private.feedback_blocks force row level security;
