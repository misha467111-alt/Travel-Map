-- Additive Screen 2 filter support. The v1 bounded RPC remains unchanged.

alter table public.locations
  add column if not exists opening_hours jsonb,
  add column if not exists timezone text,
  add column if not exists is_family_friendly boolean;

create or replace function public.travel_opening_hours_is_valid(value jsonb)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select jsonb_typeof(value) = 'object'
    and value ?& array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
    and not exists (
      select 1
      from jsonb_object_keys(value) as key
      where key <> all (array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
    )
    and not exists (
      select 1
      from jsonb_each(value) as day(key, intervals)
      where jsonb_typeof(intervals) <> 'array'
         or exists (
           select 1
           from jsonb_array_elements(intervals) as item(value)
           where jsonb_typeof(item.value) <> 'object'
              or not (item.value ?& array['open', 'close'])
              or exists (
                select 1
                from jsonb_object_keys(item.value) as interval_key
                where interval_key <> all (array['open', 'close'])
              )
              or (item.value ->> 'open')
                   !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
              or (item.value ->> 'close')
                   !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
         )
    )
$$;

alter table public.locations
  drop constraint if exists locations_opening_hours_canonical_check;
alter table public.locations
  add constraint locations_opening_hours_canonical_check
  check (
    opening_hours is null
    or public.travel_opening_hours_is_valid(opening_hours)
  );

create or replace function public.travel_validate_location_filter_metadata()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.timezone is not null
     and not exists (
       select 1 from pg_catalog.pg_timezone_names
       where name = new.timezone
     ) then
    raise exception 'invalid IANA timezone: %', new.timezone;
  end if;
  return new;
end
$$;

drop trigger if exists locations_filter_metadata_validate
  on public.locations;
create trigger locations_filter_metadata_validate
before insert or update of opening_hours, timezone, is_family_friendly
on public.locations
for each row execute function public.travel_validate_location_filter_metadata();

alter table public.locations
  drop constraint if exists locations_category_check;
alter table public.locations
  add constraint locations_category_check check (
    category in (
      'general', 'cafe', 'nature', 'culture', 'entertainment',
      'active_outdoors', 'viewpoints', 'historic', 'events', 'romance',
      'shopping', 'kids'
    )
  );

insert into public.categories (slug, name, icon, is_active)
values
  ('general', 'Загальне', 'place', true),
  ('cafe', 'Кафе', 'local_cafe', true),
  ('nature', 'Природа', 'park', true),
  ('culture', 'Культура', 'museum', true),
  ('entertainment', 'Розваги', 'theater_comedy', true),
  ('active_outdoors', 'Активний відпочинок', 'directions_run', true),
  ('viewpoints', 'Оглядові місця', 'photo_camera', true),
  ('historic', 'Історичні місця', 'castle', true),
  ('events', 'Події', 'music_note', true),
  ('romance', 'Романтика', 'favorite', true),
  ('shopping', 'Шопінг', 'shopping_bag', true),
  ('kids', 'Для дітей', 'child_care', true)
on conflict (slug) do update
set name = excluded.name,
    icon = excluded.icon,
    is_active = excluded.is_active,
    updated_at = now();

create or replace function public.travel_location_is_open_now(
  schedule jsonb,
  location_timezone text,
  at_time timestamptz default now()
)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  day_keys constant text[] := array['mon','tue','wed','thu','fri','sat','sun'];
  local_value timestamp;
  local_clock time;
  day_index integer;
  previous_index integer;
  interval_value jsonb;
  opens_at time;
  closes_at time;
begin
  if schedule is null or location_timezone is null then
    return false;
  end if;

  local_value := at_time at time zone location_timezone;
  local_clock := local_value::time;
  day_index := extract(isodow from local_value)::integer;
  previous_index := case when day_index = 1 then 7 else day_index - 1 end;

  for interval_value in
    select value from jsonb_array_elements(schedule -> day_keys[day_index])
  loop
    opens_at := (interval_value ->> 'open')::time;
    closes_at := (interval_value ->> 'close')::time;
    if opens_at = closes_at
       or (opens_at < closes_at and local_clock >= opens_at and local_clock < closes_at)
       or (opens_at > closes_at and local_clock >= opens_at) then
      return true;
    end if;
  end loop;

  for interval_value in
    select value from jsonb_array_elements(schedule -> day_keys[previous_index])
  loop
    opens_at := (interval_value ->> 'open')::time;
    closes_at := (interval_value ->> 'close')::time;
    if opens_at > closes_at and local_clock < closes_at then
      return true;
    end if;
  end loop;

  return false;
end
$$;

create or replace function public.travel_locations_in_bounds_v2(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_category text default null,
  p_search text default null,
  p_user_latitude double precision default null,
  p_user_longitude double precision default null,
  p_max_distance_m double precision default null,
  p_min_rating numeric default null,
  p_open_now boolean default false,
  p_family_friendly_only boolean default false,
  p_sort text default 'newest',
  p_limit integer default 300
)
returns table (
  id uuid,
  user_id uuid,
  title text,
  description text,
  coordinates jsonb,
  created_at timestamptz,
  image_url text,
  category text,
  status text,
  visibility text,
  moderation text,
  updated_at timestamptz,
  author_name text,
  author_avatar_url text,
  rating numeric,
  ratings_count integer,
  opening_hours jsonb,
  timezone text,
  is_family_friendly boolean,
  distance_m double precision,
  total_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with filtered as (
    select
      l.id,
      l.owner_id as user_id,
      l.name as title,
      l.description,
      public.st_asgeojson(l.position::public.geometry)::jsonb as coordinates,
      l.created_at,
      l.image_url,
      l.category,
      l.status::text as status,
      l.visibility::text as visibility,
      l.moderation,
      l.updated_at,
      coalesce(
        nullif(trim(p.display_name), ''),
        nullif(trim(p.username), ''),
        'Мандрівник'
      ) as author_name,
      p.avatar_url as author_avatar_url,
      l.rating,
      l.ratings_count,
      l.opening_hours,
      l.timezone,
      l.is_family_friendly,
      case
        when p_user_latitude is not null and p_user_longitude is not null
        then public.st_distance(
          l.position,
          public.st_setsrid(
            public.st_makepoint(p_user_longitude, p_user_latitude), 4326
          )::public.geography
        )
      end as distance_m
    from public.locations l
    left join public.profiles p on p.id = l.owner_id
    where l.status = 'approved'::public.location_status
      and l.visibility in (
        'public'::public.location_visibility,
        'unlisted'::public.location_visibility
      )
      and l.position operator(public.&&) public.st_makeenvelope(
        least(p_min_lng, p_max_lng),
        least(p_min_lat, p_max_lat),
        greatest(p_min_lng, p_max_lng),
        greatest(p_min_lat, p_max_lat),
        4326
      )::public.geography
      and (p_category is null or l.category = p_category)
      and (
        coalesce(trim(p_search), '') = ''
        or l.name ilike '%' || trim(p_search) || '%'
      )
      and (p_min_rating is null or l.rating >= p_min_rating)
      and (
        not coalesce(p_family_friendly_only, false)
        or l.is_family_friendly is true
      )
      and (
        not coalesce(p_open_now, false)
        or public.travel_location_is_open_now(
          l.opening_hours,
          l.timezone,
          now()
        )
      )
      and (
        p_max_distance_m is null
        or (
          p_user_latitude is not null
          and p_user_longitude is not null
          and public.st_dwithin(
            l.position,
            public.st_setsrid(
              public.st_makepoint(p_user_longitude, p_user_latitude), 4326
            )::public.geography,
            least(greatest(p_max_distance_m, 1), 10000000)
          )
        )
      )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
  )
  select * from counted
  order by
    case when p_sort = 'nearest' then distance_m end asc nulls last,
    case when p_sort = 'rating' then rating end desc nulls last,
    case when p_sort = 'rating' then ratings_count end desc nulls last,
    case when p_sort = 'newest' or p_sort not in ('nearest', 'rating')
      then created_at end desc,
    created_at desc,
    id desc
  limit least(greatest(coalesce(p_limit, 300), 1), 500)
$$;

create index if not exists locations_rating_created_idx
  on public.locations (rating desc, created_at desc, id desc);
create index if not exists locations_family_friendly_idx
  on public.locations (created_at desc, id desc)
  where is_family_friendly is true;

revoke all on function public.travel_opening_hours_is_valid(jsonb) from public;
revoke all on function public.travel_location_is_open_now(jsonb, text, timestamptz)
  from public;
revoke all on function public.travel_validate_location_filter_metadata()
  from public;
revoke all on function public.travel_locations_in_bounds_v2(
  double precision, double precision, double precision, double precision,
  text, text, double precision, double precision, double precision, numeric,
  boolean, boolean, text, integer
) from public;

grant execute on function public.travel_locations_in_bounds_v2(
  double precision, double precision, double precision, double precision,
  text, text, double precision, double precision, double precision, numeric,
  boolean, boolean, text, integer
) to authenticated;
grant execute on function public.travel_location_is_open_now(jsonb, text, timestamptz)
  to authenticated;
