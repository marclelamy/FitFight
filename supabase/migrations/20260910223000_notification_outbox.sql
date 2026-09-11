-- Private APNs installations and final-sync notification outbox. No client grants.

create table private.device_installations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  token_fingerprint text not null unique,
  encrypted_token text not null,
  encryption_iv text not null,
  encryption_tag text not null,
  apns_environment text not null,
  bundle_id text not null default 'com.fitfight.mvp',
  locale text,
  permission_status text,
  last_registered_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoke_reason text,
  constraint device_installations_fingerprint_nonempty check (token_fingerprint <> ''),
  constraint device_installations_token_nonempty check (encrypted_token <> ''),
  constraint device_installations_iv_nonempty check (encryption_iv <> ''),
  constraint device_installations_tag_nonempty check (encryption_tag <> ''),
  constraint device_installations_apns_environment check (
    apns_environment in ('sandbox', 'production')
  )
);

create table private.notification_intents (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  fight_id uuid not null references public.fights (id) on delete cascade,
  kind text not null,
  slot text not null,
  not_before timestamptz not null,
  expires_at timestamptz not null,
  route text not null,
  copy_key text not null,
  status text not null default 'pending',
  skip_reason text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  constraint notification_intents_idempotency_nonempty check (idempotency_key <> ''),
  constraint notification_intents_kind check (
    kind in ('fight_ended', 'grace_reminder', 'fight_finalized')
  ),
  constraint notification_intents_slot check (
    slot in ('t0', 't12', 't18', 't23', 'final')
  ),
  constraint notification_intents_status check (
    status in ('pending', 'skipped', 'sent', 'failed', 'expired')
  ),
  constraint notification_intents_skip_reason check (
    skip_reason is null
    or skip_reason in (
      'already_complete', 'no_token', 'muted', 'superseded', 'fight_cancelled'
    )
  ),
  constraint notification_intents_window check (expires_at > not_before)
);

create table private.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  intent_id uuid not null references private.notification_intents (id) on delete cascade,
  installation_id uuid references private.device_installations (id) on delete set null,
  attempt integer not null,
  apns_http_status integer,
  apns_reason text,
  sent_at timestamptz not null default now(),
  constraint notification_deliveries_attempt_positive check (attempt >= 1)
);

create index notification_intents_pending_due_idx
  on private.notification_intents (status, not_before)
  where status = 'pending';

create index device_installations_active_user_idx
  on private.device_installations (user_id)
  where revoked_at is null;

alter table private.device_installations enable row level security;
alter table private.notification_intents enable row level security;
alter table private.notification_deliveries enable row level security;
revoke all on table private.device_installations from anon, authenticated, public;
revoke all on table private.notification_intents from anon, authenticated, public;
revoke all on table private.notification_deliveries from anon, authenticated, public;
grant all on table private.device_installations to postgres, service_role;
grant all on table private.notification_intents to postgres, service_role;
grant all on table private.notification_deliveries to postgres, service_role;
