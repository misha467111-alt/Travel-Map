alter table public.locations
  add column if not exists request_id uuid;

create unique index if not exists locations_owner_request_id_uidx
  on public.locations(owner_id, request_id)
  where request_id is not null;

create function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude double precision,
  location_longitude double precision,
  p_image_url text,
  p_category text,
  p_request_id uuid
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
  if uid is null then raise exception 'authentication required'; end if;
  if nullif(btrim(location_title), '') is null then raise exception 'title required'; end if;
  if location_latitude not between -90 and 90
     or location_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;

  if p_request_id is not null then
    select id into location_id
    from public.locations
    where owner_id = uid and request_id = p_request_id;
    if location_id is not null then return location_id; end if;
  end if;

  begin
    insert into public.locations(
      user_id, owner_id, title, name, description, coordinates, position,
      status, visibility, moderation, secrecy, category, image_url, request_id
    ) values (
      uid, uid, btrim(location_title), btrim(location_title),
      coalesce(btrim(location_description), ''),
      st_setsrid(st_makepoint(location_longitude, location_latitude), 4326)::geography,
      st_setsrid(st_makepoint(location_longitude, location_latitude), 4326)::geography,
      'draft', 'public', 'draft', 'public', normalized_category,
      nullif(btrim(p_image_url), ''), p_request_id
    ) returning id into location_id;
  exception when unique_violation then
    if p_request_id is null then raise; end if;
    select id into location_id from public.locations
    where owner_id = uid and request_id = p_request_id;
    if location_id is null then raise; end if;
    return location_id;
  end;

  update public.profiles
  set xp = coalesce(xp, 0) + 10
  where id = uid or user_id = uid;

  return location_id;
end
$$;

revoke all on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text, uuid
) from public;
grant execute on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text, uuid
) to authenticated;
