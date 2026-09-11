-- Freeze finished Fight scores and completed civil days.
-- A civil day is complete when it is strictly before complete_through's
-- local date. Fight results freeze when state becomes final. Set
-- fitfight.allow_score_correction = on only for an audited backfill.

alter table public.fight_members
  add column if not exists calculation_version integer not null default 1,
  add column if not exists scoring_engine_version integer not null default 1;

create or replace function private.allow_score_correction()
returns boolean
language sql
stable
as $$
  select coalesce(nullif(current_setting('fitfight.allow_score_correction', true), ''), '') = 'on';
$$;

create or replace function private.strip_member_scores_on_insert()
returns trigger
language plpgsql
as $$
begin
  if private.allow_score_correction() then
    return new;
  end if;
  new.current_value := null;
  new.rank := null;
  new.outcome_minor := null;
  new.final_value := null;
  new.finalized_at := null;
  new.input_revision := null;
  new.freshness := null;
  new.calculation_version := 1;
  new.scoring_engine_version := 1;
  return new;
end;
$$;

create or replace function private.protect_final_fight()
returns trigger
language plpgsql
as $$
begin
  if old.state = 'final' and not private.allow_score_correction() then
    new.state := 'final';
    new.metric := old.metric;
    new.metric_definition_version := old.metric_definition_version;
    new.outcome_rule := old.outcome_rule;
    new.goal_policy := old.goal_policy;
    new.default_goal_value := old.default_goal_value;
    new.tie_rule := old.tie_rule;
    new.starts_at := old.starts_at;
    new.ends_at := old.ends_at;
    new.scoring_engine_version := old.scoring_engine_version;
    new.rules_version := old.rules_version;
    new.stake_minor := old.stake_minor;
    new.stake_kind := old.stake_kind;
    new.time_zone := old.time_zone;
    new.name := old.name;
    new.final_sync_grace_seconds := old.final_sync_grace_seconds;
    new.action_text := old.action_text;
    new.series_id := old.series_id;
  end if;
  return new;
end;
$$;

create or replace function private.freeze_fight_members_on_final()
returns trigger
language plpgsql
as $$
begin
  if new.state = 'final' and old.state is distinct from 'final' then
    update public.fight_members
    set
      final_value = coalesce(final_value, current_value),
      finalized_at = coalesce(finalized_at, clock_timestamp()),
      calculation_version = coalesce(calculation_version, 1),
      scoring_engine_version = coalesce(scoring_engine_version, new.scoring_engine_version)
    where fight_id = new.id
      and state = 'accepted'
      and finalized_at is null;

    update private.fight_score_snapshots as snapshot
    set is_final = true
    from (
      select distinct on (snapshot.user_id) snapshot.id
      from private.fight_score_snapshots as snapshot
      join public.fight_members as member
        on member.fight_id = snapshot.fight_id
        and member.user_id = snapshot.user_id
        and member.selected_source_id = snapshot.source_id
        and member.state = 'accepted'
      where snapshot.fight_id = new.id
      order by snapshot.user_id, snapshot.cutoff_at desc, snapshot.created_at desc, snapshot.id desc
    ) as latest
    where snapshot.id = latest.id
      and snapshot.is_final = false;
  end if;
  return new;
end;
$$;

create or replace function private.protect_finalized_member_scores()
returns trigger
language plpgsql
as $$
begin
  if old.finalized_at is not null and not private.allow_score_correction() then
    new.current_value := old.current_value;
    new.rank := old.rank;
    new.outcome_minor := old.outcome_minor;
    new.final_value := old.final_value;
    new.finalized_at := old.finalized_at;
    new.input_revision := old.input_revision;
    new.calculation_version := old.calculation_version;
    new.scoring_engine_version := old.scoring_engine_version;
    new.selected_source_id := old.selected_source_id;
    new.source_label := old.source_label;
  end if;
  return new;
end;
$$;

create or replace function private.protect_finalized_metric_days()
returns trigger
language plpgsql
as $$
begin
  if old.finalized_at is not null and not private.allow_score_correction() then
    new.value := old.value;
    new.unit := old.unit;
    new.input_hash := old.input_hash;
    new.normalization_version := old.normalization_version;
    new.calculation_version := old.calculation_version;
    new.finalized_at := old.finalized_at;
  end if;
  return new;
end;
$$;

create or replace function private.protect_final_fight_snapshots()
returns trigger
language plpgsql
as $$
begin
  if old.is_final and not private.allow_score_correction() then
    new.value := old.value;
    new.input_hash := old.input_hash;
    new.calculation_version := old.calculation_version;
    new.cutoff_at := old.cutoff_at;
    new.is_final := true;
    new.source_id := old.source_id;
  end if;
  return new;
end;
$$;

create or replace function private.protect_finalized_step_days()
returns trigger
language plpgsql
as $$
declare
  frozen integer;
begin
  if private.allow_score_correction() then
    return new;
  end if;
  select md.value::integer
    into frozen
  from public.metric_days as md
  where md.user_id = old.user_id
    and md.day = old.day
    and md.finalized_at is not null
  order by md.updated_at desc
  limit 1;
  if found then
    new.steps := frozen;
  end if;
  return new;
end;
$$;

drop trigger if exists strip_member_scores_on_insert on public.fight_members;
create trigger strip_member_scores_on_insert
  before insert on public.fight_members
  for each row
  execute function private.strip_member_scores_on_insert();

drop trigger if exists protect_final_fight on public.fights;
create trigger protect_final_fight
  before update on public.fights
  for each row
  execute function private.protect_final_fight();

drop trigger if exists freeze_fight_members_on_final on public.fights;
create trigger freeze_fight_members_on_final
  after update on public.fights
  for each row
  execute function private.freeze_fight_members_on_final();

drop trigger if exists protect_finalized_member_scores on public.fight_members;
create trigger protect_finalized_member_scores
  before update on public.fight_members
  for each row
  execute function private.protect_finalized_member_scores();

drop trigger if exists protect_finalized_metric_days on public.metric_days;
create trigger protect_finalized_metric_days
  before update on public.metric_days
  for each row
  execute function private.protect_finalized_metric_days();

drop trigger if exists protect_final_fight_snapshots on private.fight_score_snapshots;
create trigger protect_final_fight_snapshots
  before update on private.fight_score_snapshots
  for each row
  execute function private.protect_final_fight_snapshots();

drop trigger if exists protect_finalized_step_days on public.step_days;
create trigger protect_finalized_step_days
  before update on public.step_days
  for each row
  execute function private.protect_finalized_step_days();

update public.fight_members as member
set
  final_value = coalesce(member.final_value, member.current_value),
  finalized_at = coalesce(member.finalized_at, clock_timestamp()),
  scoring_engine_version = coalesce(member.scoring_engine_version, fight.scoring_engine_version)
from public.fights as fight
where fight.id = member.fight_id
  and fight.state = 'final'
  and member.state = 'accepted'
  and member.finalized_at is null;

update private.fight_score_snapshots as snapshot
set is_final = true
from (
  select distinct on (snapshot.fight_id, snapshot.user_id) snapshot.id
  from private.fight_score_snapshots as snapshot
  join public.fight_members as member
    on member.fight_id = snapshot.fight_id
    and member.user_id = snapshot.user_id
    and member.selected_source_id = snapshot.source_id
    and member.state = 'accepted'
  where snapshot.fight_id in (select id from public.fights where state = 'final')
  order by snapshot.fight_id, snapshot.user_id, snapshot.cutoff_at desc, snapshot.created_at desc, snapshot.id desc
) as latest
where snapshot.id = latest.id
  and snapshot.is_final = false;
