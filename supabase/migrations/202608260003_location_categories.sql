begin;

alter table public.locations
  add column if not exists category text not null default 'general';

alter table public.locations
  drop constraint if exists locations_category_check;

alter table public.locations
  add constraint locations_category_check check (
    category in ('general', 'cafe', 'nature', 'culture', 'entertainment')
  );

create index if not exists locations_category_idx
  on public.locations(category);

drop function if exists public.create_location_with_xp(
  text, text, double precision, double precision, text, text
);

create function public.create_location_with_xp(
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
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  created_location_id uuid;
  normalized_category text := coalesce(nullif(btrim(p_category), ''), 'general');
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if nullif(btrim(location_title), '') is null then
    raise exception 'location title is required';
  end if;
  if location_latitude not between -90 and 90
     or location_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  if normalized_category not in (
    'general', 'cafe', 'nature', 'culture', 'entertainment'
  ) then raise exception 'invalid location category'; end if;
  if p_image_url is not null and length(p_image_url) > 2048 then
    raise exception 'image URL is too long';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute $insert$
      insert into public.locations (
        user_id, title, description, coordinates, image_url, category
      ) values (
        $1, $2, $3,
        extensions.st_setsrid(extensions.st_makepoint($4, $5), 4326)
          ::extensions.geography,
        $6, $7
      ) returning id
    $insert$
    into created_location_id
    using current_user_id, btrim(location_title),
      coalesce(btrim(location_description), ''), location_longitude,
      location_latitude, nullif(btrim(p_image_url), ''), normalized_category;
  else
    execute $insert$
      insert into public.locations (
        owner_id, name, description, position, image_url, category
      ) values (
        $1, $2, $3,
        extensions.st_setsrid(extensions.st_makepoint($4, $5), 4326)
          ::extensions.geography,
        $6, $7
      ) returning id
    $insert$
    into created_location_id
    using current_user_id, btrim(location_title),
      coalesce(btrim(location_description), ''), location_longitude,
      location_latitude, nullif(btrim(p_image_url), ''), normalized_category;
  end if;

  update public.profiles set xp = xp + 10 where id = current_user_id;
  if not found then raise exception 'profile not found'; end if;
  return created_location_id;
end;
$$;

revoke all on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text
) from public;
grant execute on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text
) to authenticated;

create or replace function public.update_own_location(
  p_location_id uuid,
  p_title text,
  p_description text,
  p_category text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized_category text := coalesce(nullif(btrim(p_category), ''), 'general');
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if nullif(btrim(p_title), '') is null then raise exception 'title is required'; end if;
  if normalized_category not in (
    'general', 'cafe', 'nature', 'culture', 'entertainment'
  ) then raise exception 'invalid location category'; end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    update public.locations set title = btrim(p_title),
      description = coalesce(btrim(p_description), ''),
      category = normalized_category
    where id = p_location_id and user_id = auth.uid();
  else
    update public.locations set name = btrim(p_title),
      description = coalesce(btrim(p_description), ''),
      category = normalized_category
    where id = p_location_id and owner_id = auth.uid();
  end if;

  if not found then raise exception 'location not found or access denied'; end if;
end;
$$;

revoke all on function public.update_own_location(uuid, text, text, text)
  from public;
grant execute on function public.update_own_location(uuid, text, text, text)
  to authenticated;

commit;
