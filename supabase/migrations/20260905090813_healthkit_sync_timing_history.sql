create table private.healthkit_sync_attempts (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  attempt_id uuid not null,
  trigger text not null check (trigger in ('observer', 'foreground', 'manual')),
  started_at timestamptz not null,
  received_at timestamptz not null default clock_timestamp(),
  outcome text not null check (outcome in ('succeeded', 'failed', 'cancelled')),
  error_code text check (
    error_code in (
      'authentication_unavailable', 'network_unavailable',
      'protected_data_unavailable', 'attempt_expired', 'healthkit_unavailable',
      'background_delivery_unavailable', 'sync_failed'
    )
  ),
  total_ms double precision not null check (total_ms >= 0 and total_ms <= 604800000),
  stages jsonb not null check (
    jsonb_typeof(stages) = 'array' and jsonb_array_length(stages) <= 256
  ),
  fight_count integer check (fight_count between 0 and 100),
  day_count integer check (day_count between 0 and 400),
  payload_bytes integer check (payload_bytes between 0 and 1000000),
  app_version text not null check (length(app_version) between 1 and 40),
  app_build text not null check (length(app_build) between 1 and 40),
  primary key (user_id, attempt_id)
);

create index healthkit_sync_attempts_user_received_idx
  on private.healthkit_sync_attempts (user_id, received_at desc, attempt_id desc);

alter table private.healthkit_sync_attempts enable row level security;
revoke all on table private.healthkit_sync_attempts from anon, authenticated, public;
grant all on table private.healthkit_sync_attempts to postgres, service_role;
