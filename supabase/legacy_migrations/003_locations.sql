begin;

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- Existing Supabase projects may have PostGIS installed either in `public`
-- or in `extensions`. Resolve its types and functions from both locations.
set local search_path = public, extensions, pg_catalog;

do $types$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'location_status'
  ) then
    create type public.location_status as enum (
      'draft', 'pending', 'approved', 'rejected', 'archived'
    );
  end if;

  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'location_visibility'
  ) then
    create type public.location_visibility as enum (
      'public', 'unlisted', 'secret', 'private'
    );
  end if;
end
$types$;

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 3 and 120),
  description text not null default '' check (char_length(description) <= 5000),
  position geography(Point, 4326) not null,
  status public.location_status not null default 'draft',
  visibility public.location_visibility not null default 'public',

  -- Compatibility fields for RPCs from the previous schema generation.
  moderation text not null default 'draft',
  secrecy text not null default 'public',
  road_difficulty text not null default 'easy',
  has_parking boolean not null default false,
  safety text not null default 'unknown',
  minimum_xp integer not null default 0 check (minimum_xp >= 0),

  rating numeric(3, 2) not null default 0
    check (rating between 0 and 5),
  ratings_count integer not null default 0 check (ratings_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint locations_position_valid_check check (
    st_isvalid(position::geometry)
    and st_srid(position::geometry) = 4326
  )
);

-- Upgrade an earlier locations table without recreating user data.
alter table public.locations add column if not exists owner_id uuid;
alter table public.locations add column if not exists name text;
alter table public.locations add column if not exists description text default '';
alter table public.locations
  add column if not exists position geography(Point, 4326);
alter table public.locations
  add column if not exists status public.location_status;
alter table public.locations
  add column if not exists visibility public.location_visibility;
alter table public.locations
  add column if not exists moderation text;
alter table public.locations
  add column if not exists secrecy text;
alter table public.locations add column if not exists road_difficulty text default 'easy';
alter table public.locations add column if not exists has_parking boolean default false;
alter table public.locations add column if not exists safety text default 'unknown';
alter table public.locations add column if not exists minimum_xp integer default 0;
alter table public.locations add column if not exists rating numeric(3, 2) default 0;
alter table public.locations add column if not exists ratings_count integer default 0;
alter table public.locations add column if not exists created_at timestamptz default now();
alter table public.locations add column if not exists updated_at timestamptz default now();

do $legacy_locations$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute $sql$
      update public.locations
      set owner_id = case
        when user_id::text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then user_id::text::uuid
        else null
      end
      where owner_id is null
    $sql$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'title'
  ) then
    execute $sql$
      update public.locations
      set name = nullif(btrim(title::text), '')
      where name is null
    $sql$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'coordinates'
  ) then
    execute $sql$
      update public.locations
      set position = coordinates::geography
      where position is null and coordinates is not null
    $sql$;
  elsif exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'latitude'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'longitude'
  ) then
    execute $sql$
      update public.locations
      set position = st_setsrid(
        st_makepoint(longitude::double precision, latitude::double precision),
        4326
      )::geography
      where position is null and latitude is not null and longitude is not null
    $sql$;
  end if;

  if exists (
    select 1 from public.locations
    where owner_id is null or name is null or position is null
  ) then
    raise exception
      'Cannot migrate locations: owner_id, name, or position is missing in legacy rows'
      using errcode = '23502';
  end if;
end
$legacy_locations$;

alter table public.locations alter column owner_id set not null;
alter table public.locations alter column name set not null;
alter table public.locations alter column description set default '';
alter table public.locations alter column description set not null;
alter table public.locations alter column position set not null;

update public.locations
set status = case lower(coalesce(moderation::text, 'draft'))
  when 'pending' then 'pending'::public.location_status
  when 'approved' then 'approved'::public.location_status
  when 'rejected' then 'rejected'::public.location_status
  when 'archived' then 'archived'::public.location_status
  else 'draft'::public.location_status
end
where status is null;

update public.locations
set visibility = case lower(coalesce(secrecy::text, 'public'))
  when 'unlisted' then 'unlisted'::public.location_visibility
  when 'secret' then 'secret'::public.location_visibility
  when 'private' then 'private'::public.location_visibility
  when 'hidden' then 'secret'::public.location_visibility
  else 'public'::public.location_visibility
end
where visibility is null;

update public.locations
set moderation = status::text
where moderation is null or moderation is distinct from status::text;

update public.locations
set secrecy = visibility::text
where secrecy is null or secrecy is distinct from visibility::text;

alter table public.locations alter column status set default 'draft';
alter table public.locations alter column status set not null;
alter table public.locations alter column visibility set default 'public';
alter table public.locations alter column visibility set not null;
alter table public.locations alter column moderation set default 'draft';
alter table public.locations alter column moderation set not null;
alter table public.locations alter column secrecy set default 'public';
alter table public.locations alter column secrecy set not null;

create index if not exists locations_position_gist_idx
  on public.locations using gist (position);
create index if not exists locations_public_feed_idx
  on public.locations (status, visibility, created_at desc);
create index if not exists locations_owner_idx
  on public.locations (owner_id, created_at desc);

create or replace function public.protect_location_system_fields()
returns trigger
language plpgsql
set search_path = 'extensions', 'public', 'pg_catalog'
as $$
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' then
      new.owner_id := auth.uid();
      new.status := 'draft';
      new.moderation := 'draft';
      new.rating := 0;
      new.ratings_count := 0;
      new.minimum_xp := 0;
    end if;
    new.created_at := coalesce(new.created_at, now());
  elsif current_user = 'authenticated' and (
    new.id is distinct from old.id
    or new.owner_id is distinct from old.owner_id
    or new.status is distinct from old.status
    or new.moderation is distinct from old.moderation
    or new.rating is distinct from old.rating
    or new.ratings_count is distinct from old.ratings_count
    or new.minimum_xp is distinct from old.minimum_xp
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'location system fields are server-managed'
      using errcode = '42501';
  end if;

  if new.position is null then
    raise exception 'location position is required' using errcode = '23502';
  end if;

  if st_srid(new.position::geometry) <> 4326 then
    raise exception 'location position must use SRID 4326'
      using errcode = '22023';
  end if;

  -- Canonical fields always drive legacy compatibility fields.
  new.moderation := new.status::text;
  new.secrecy := new.visibility::text;
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists locations_protect_system_fields on public.locations;
create trigger locations_protect_system_fields
before insert or update on public.locations
for each row execute function public.protect_location_system_fields();

alter table public.locations enable row level security;

do $drop_legacy_location_policies$
declare
  policy_record record;
begin
  for policy_record in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'locations'
  loop
    execute format(
      'drop policy if exists %I on public.locations',
      policy_record.policyname
    );
  end loop;
end
$drop_legacy_location_policies$;

create policy locations_select_visible
on public.locations for select
to authenticated
using (
  owner_id = (select auth.uid())
  or (
    status = 'approved'
    and visibility in ('public', 'unlisted')
  )
);

create policy locations_insert_self
on public.locations for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and status = 'draft'
  and moderation = 'draft'
  and rating = 0
  and ratings_count = 0
  and minimum_xp = 0
);

create policy locations_update_draft_self
on public.locations for update
to authenticated
using (
  owner_id = (select auth.uid())
  and status in ('draft', 'rejected')
)
with check (
  owner_id = (select auth.uid())
  and status in ('draft', 'rejected')
);

create policy locations_delete_draft_self
on public.locations for delete
to authenticated
using (
  owner_id = (select auth.uid())
  and status in ('draft', 'rejected')
);

revoke all on table public.locations from anon, authenticated;
grant select on table public.locations to authenticated;
grant insert (
  name,
  description,
  position,
  visibility,
  road_difficulty,
  has_parking,
  safety
) on public.locations to authenticated;
grant update (
  name,
  description,
  position,
  visibility,
  road_difficulty,
  has_parking,
  safety
) on public.locations to authenticated;
grant delete on table public.locations to authenticated;

revoke all on function public.protect_location_system_fields() from public;

commit;
