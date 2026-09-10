begin;

alter table public.profiles add column if not exists xp integer;
alter table public.profiles add column if not exists level text;

update public.profiles set xp = 0 where xp is null;
update public.profiles
set level = case
  when xp >= 500 then 'Мандрівник'
  when xp >= 100 then 'Дослідник'
  else 'Новачок'
end
where level is null or btrim(level) = '';

alter table public.profiles alter column xp set default 0;
alter table public.profiles alter column xp set not null;
alter table public.profiles alter column level set default 'Новачок';
alter table public.profiles alter column level set not null;

create or replace function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude double precision,
  location_longitude double precision
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  created_location_id uuid;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if nullif(btrim(location_title), '') is null then
    raise exception 'location title is required';
  end if;
  if location_latitude not between -90 and 90
     or location_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute $insert$
      insert into public.locations (user_id, title, description, coordinates)
      values (
        $1,
        $2,
        $3,
        extensions.st_setsrid(extensions.st_makepoint($4, $5), 4326)::extensions.geography
      )
      returning id
    $insert$
    into created_location_id
    using current_user_id, btrim(location_title), coalesce(btrim(location_description), ''),
      location_longitude, location_latitude;
  else
    execute $insert$
      insert into public.locations (owner_id, name, description, position)
      values (
        $1,
        $2,
        $3,
        extensions.st_setsrid(extensions.st_makepoint($4, $5), 4326)::extensions.geography
      )
      returning id
    $insert$
    into created_location_id
    using current_user_id, btrim(location_title), coalesce(btrim(location_description), ''),
      location_longitude, location_latitude;
  end if;

  update public.profiles
  set
    xp = xp + 10,
    level = case
      when xp + 10 >= 500 then 'Мандрівник'
      when xp + 10 >= 100 then 'Дослідник'
      else 'Новачок'
    end
  where id = current_user_id;

  if not found then
    raise exception 'profile not found';
  end if;

  return created_location_id;
end;
$$;

revoke all on function public.create_location_with_xp(text, text, double precision, double precision) from public;
grant execute on function public.create_location_with_xp(text, text, double precision, double precision) to authenticated;

commit;
