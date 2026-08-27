-- Keep the canonical six-argument RPC compatible with the live compatibility
-- columns that still have NOT NULL constraints.
create or replace function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude double precision,
  location_longitude double precision,
  p_image_url text default null,
  p_category text default 'general'
)
returns uuid
language plpgsql
security definer
set search_path = 'extensions', 'public', 'pg_catalog'
as $$
declare
  uid uuid := auth.uid();
  location_id uuid;
  normalized_category text := coalesce(nullif(btrim(p_category), ''), 'general');
begin
  if uid is null then
    raise exception 'authentication required';
  end if;
  if nullif(btrim(location_title), '') is null then
    raise exception 'title required';
  end if;
  if location_latitude not between -90 and 90
     or location_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;

  insert into public.locations(
    user_id, owner_id, title, name, description, coordinates, position,
    status, visibility, moderation, secrecy, category, image_url
  ) values (
    uid, uid, btrim(location_title), btrim(location_title),
    coalesce(btrim(location_description), ''),
    st_setsrid(st_makepoint(location_longitude, location_latitude), 4326)::geography,
    st_setsrid(st_makepoint(location_longitude, location_latitude), 4326)::geography,
    'draft', 'public', 'draft', 'public', normalized_category,
    nullif(btrim(p_image_url), '')
  )
  returning id into location_id;

  update public.profiles
  set xp = coalesce(xp, 0) + 10
  where id = uid or user_id = uid;

  return location_id;
end
$$;
