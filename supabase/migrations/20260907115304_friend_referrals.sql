alter table public.profiles add column referral_code uuid not null unique default gen_random_uuid();

create table private.referrals (
  referred_user_id uuid primary key references public.profiles (user_id) on delete cascade,
  referrer_user_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint referrals_not_self check (referred_user_id <> referrer_user_id)
);

create index referrals_referrer_idx on private.referrals (referrer_user_id);

alter table private.referrals enable row level security;
revoke all on table private.referrals from anon, authenticated, public;
grant all on table private.referrals to postgres, service_role;
