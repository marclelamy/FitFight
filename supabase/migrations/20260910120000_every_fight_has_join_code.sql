-- Every fight series has a join code. Public vs private only changes the Join list.

create function pg_temp.random_join_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  code text;
  i integer;
begin
  loop
    code := '';
    for i in 1..4 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
    end loop;
    exit when not exists (
      select 1 from public.fight_series where join_code = code
    );
  end loop;
  return code;
end;
$$;

do $$
declare
  fight record;
  series_id uuid;
begin
  for fight in
    select id, owner_id, name, action_text, time_zone, starts_at, ends_at
    from public.fights
    where series_id is null
      and owner_id is not null
  loop
    insert into public.fight_series (
      owner_id,
      join_code,
      visibility,
      recurring,
      duration_seconds,
      name,
      action_text,
      time_zone,
      current_fight_id
    ) values (
      fight.owner_id,
      pg_temp.random_join_code(),
      'invite_only',
      false,
      greatest(1, extract(epoch from (fight.ends_at - fight.starts_at))::integer),
      fight.name,
      fight.action_text,
      fight.time_zone,
      fight.id
    )
    returning id into series_id;

    update public.fights
    set series_id = series_id
    where id = fight.id;

    insert into public.fight_series_members (series_id, user_id, state)
    select series_id, user_id, state
    from public.fight_members
    where fight_id = fight.id
      and state in ('accepted', 'deferred')
    on conflict (series_id, user_id) do nothing;

    insert into public.fight_series_members (series_id, user_id, state)
    values (series_id, fight.owner_id, 'accepted')
    on conflict (series_id, user_id) do nothing;
  end loop;

  for series_id in
    select id from public.fight_series where join_code is null
  loop
    update public.fight_series
    set join_code = pg_temp.random_join_code()
    where id = series_id;
  end loop;
end;
$$;

alter table public.fight_series
  drop constraint fight_series_joinable_has_code;

alter table public.fight_series
  alter column join_code set not null;
