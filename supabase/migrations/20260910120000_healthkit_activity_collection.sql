-- Private Apple Health activity collection. Not used for Fight scoring.

create table private.healthkit_activity_days (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid not null references public.data_sources (id) on delete cascade,
  metric text not null,
  day date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  value numeric not null,
  unit text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, source_id, metric, day),
  constraint healthkit_activity_days_window check (ends_at > starts_at),
  constraint healthkit_activity_days_value_nonnegative check (value >= 0),
  constraint healthkit_activity_days_metric check (
    metric in (
      'active_energy',
      'walking_running_distance',
      'exercise_minutes',
      'stand_minutes',
      'stand_hours',
      'flights_climbed',
      'cycling_distance',
      'swimming_distance',
      'move_time_minutes',
      'wheelchair_distance',
      'wheelchair_pushes',
      'swimming_strokes',
      'rowing_distance',
      'paddle_distance',
      'skating_distance',
      'cross_country_ski_distance',
      'downhill_snow_distance',
      'workout_count',
      'workout_time',
      'walk_run_workout_distance'
    )
  ),
  constraint healthkit_activity_days_unit check (
    (metric = 'active_energy' and unit = 'kcal')
    or (metric in (
      'walking_running_distance',
      'cycling_distance',
      'swimming_distance',
      'wheelchair_distance',
      'rowing_distance',
      'paddle_distance',
      'skating_distance',
      'cross_country_ski_distance',
      'downhill_snow_distance',
      'walk_run_workout_distance'
    ) and unit = 'm')
    or (metric in ('exercise_minutes', 'stand_minutes', 'move_time_minutes') and unit = 'min')
    or (metric in (
      'stand_hours',
      'flights_climbed',
      'wheelchair_pushes',
      'swimming_strokes',
      'workout_count'
    ) and unit = 'count')
    or (metric = 'workout_time' and unit = 's')
  )
);

create table private.healthkit_workouts (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid not null references public.data_sources (id) on delete cascade,
  healthkit_uuid uuid not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  activity_type text not null,
  duration_seconds numeric not null,
  distance_m numeric,
  energy_kcal numeric,
  effort numeric,
  updated_at timestamptz not null default now(),
  primary key (user_id, healthkit_uuid),
  constraint healthkit_workouts_window check (ended_at > started_at),
  constraint healthkit_workouts_duration check (duration_seconds >= 0),
  constraint healthkit_workouts_distance check (distance_m is null or distance_m >= 0),
  constraint healthkit_workouts_energy check (energy_kcal is null or energy_kcal >= 0),
  constraint healthkit_workouts_effort check (effort is null or effort >= 0),
  constraint healthkit_workouts_activity_type check (
    char_length(activity_type) between 1 and 64
    and activity_type ~ '^[a-z0-9_]+$'
  )
);

create index healthkit_activity_days_user_day_idx
  on private.healthkit_activity_days (user_id, day);
create index healthkit_workouts_user_started_idx
  on private.healthkit_workouts (user_id, started_at);

alter table private.healthkit_activity_days enable row level security;
alter table private.healthkit_workouts enable row level security;
revoke all on table private.healthkit_activity_days from anon, authenticated, public;
revoke all on table private.healthkit_workouts from anon, authenticated, public;
grant all on table private.healthkit_activity_days to postgres, service_role;
grant all on table private.healthkit_workouts to postgres, service_role;
