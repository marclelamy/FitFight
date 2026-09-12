-- Server-owned API failure log. Clients have no access. Agents read via SQL.

create table private.server_error_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid,
  method text not null,
  path text not null,
  action text not null,
  route_params jsonb not null default '{}'::jsonb,
  status integer not null,
  error_code text not null,
  failure text not null,
  trace jsonb not null,
  app_version text,
  app_build text,
  request_trace_id uuid,
  constraint server_error_logs_method_nonempty check (btrim(method) <> ''),
  constraint server_error_logs_path_nonempty check (btrim(path) <> ''),
  constraint server_error_logs_action_nonempty check (btrim(action) <> ''),
  constraint server_error_logs_error_code_nonempty check (btrim(error_code) <> ''),
  constraint server_error_logs_failure_nonempty check (btrim(failure) <> ''),
  constraint server_error_logs_status_range check (status between 100 and 599)
);

create index server_error_logs_created_at_idx
  on private.server_error_logs (created_at desc);

create index server_error_logs_user_id_created_at_idx
  on private.server_error_logs (user_id, created_at desc)
  where user_id is not null;

alter table private.server_error_logs enable row level security;
revoke all on table private.server_error_logs from anon, authenticated, public;
grant all on table private.server_error_logs to postgres, service_role;
