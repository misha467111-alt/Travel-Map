begin;

-- ============================================================================
-- COMPLETE PRODUCTION SCHEMA (forward-only, data-preserving)
-- Target: existing partially migrated Travel Map production database.
-- This migration is additive and intentionally keeps all legacy tables/columns.
-- ============================================================================

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- Canonical enums (create only when absent).
do $types$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'location_status'
  ) then
    create type public.location_status as enum
      ('draft','pending','approved','rejected','archived');
  end if;

  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'location_visibility'
  ) then
    create type public.location_visibility as enum
      ('public','unlisted','secret','private');
  end if;

  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'social_content_status'
  ) then
    create type public.social_content_status as enum
      ('pending','visible','hidden','deleted');
  end if;
end
$types$;

-- --------------------------------------------------------------------------
-- PROFILES: preserve legacy rows, add canonical server fields only.
-- --------------------------------------------------------------------------
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists name text default 'Дослідник';
alter table public.profiles add column if not exists display_name text default '';
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists xp integer default 0;
alter table public.profiles add column if not exists level text default 'Новачок';
alter table public.profiles add column if not exists invite_redeemed boolean default false;
alter table public.profiles add column if not exists invited_by uuid;
alter table public.profiles add column if not exists invite_balance integer default 1;
alter table public.profiles add column if not exists is_developer boolean default false;
alter table public.profiles add column if not exists distance_traveled_km numeric default 0;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles add column if not exists updated_at timestamptz default now();

-- Do not mass-update legacy orphan profile rows here. Their NOT VALID auth FK is
-- deliberately left as-is so historical data is preserved.

-- --------------------------------------------------------------------------
-- USER SETTINGS
-- --------------------------------------------------------------------------
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  locale text not null default 'uk',
  theme text not null default 'system',
  distance_unit text not null default 'metric',
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------
-- LOCATIONS: canonical aliases over legacy user_id/title/coordinates.
-- --------------------------------------------------------------------------
do $locations$
declare
  postgis_schema text;
begin
  select n.nspname into postgis_schema
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'postgis';

  if to_regclass('public.locations') is null then
    execute format($ddl$
      create table public.locations (
        id uuid primary key default gen_random_uuid(),
        owner_id uuid not null references public.profiles(id) on delete cascade,
        name text not null,
        description text not null default '',
        position %I.geography(Point,4326) not null,
        status public.location_status not null default 'draft',
        visibility public.location_visibility not null default 'public',
        moderation text not null default 'draft',
        secrecy text not null default 'public',
        category text not null default 'general',
        image_url text,
        road_difficulty text not null default 'easy',
        has_parking boolean not null default false,
        safety text not null default 'unknown',
        minimum_xp integer not null default 0,
        rating numeric(3,2) not null default 0,
        ratings_count integer not null default 0,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )
    $ddl$, postgis_schema);
  else
    alter table public.locations add column if not exists owner_id uuid;
    alter table public.locations add column if not exists name text;
    alter table public.locations add column if not exists description text default '';
    execute format(
      'alter table public.locations add column if not exists position %I.geography(Point,4326)',
      postgis_schema
    );
    alter table public.locations add column if not exists status public.location_status default 'draft';
    alter table public.locations add column if not exists visibility public.location_visibility default 'public';
    alter table public.locations add column if not exists moderation text default 'draft';
    alter table public.locations add column if not exists secrecy text default 'public';
    alter table public.locations add column if not exists category text default 'general';
    alter table public.locations add column if not exists image_url text;
    alter table public.locations add column if not exists road_difficulty text default 'easy';
    alter table public.locations add column if not exists has_parking boolean default false;
    alter table public.locations add column if not exists safety text default 'unknown';
    alter table public.locations add column if not exists minimum_xp integer default 0;
    alter table public.locations add column if not exists rating numeric(3,2) default 0;
    alter table public.locations add column if not exists ratings_count integer default 0;
    alter table public.locations add column if not exists created_at timestamptz default now();
    alter table public.locations add column if not exists updated_at timestamptz default now();

    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='locations' and column_name='user_id'
    ) then
      execute $q$
        update public.locations l
        set owner_id = l.user_id::uuid
        where l.owner_id is null
          and l.user_id is not null
          and l.user_id::text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      $q$;
    end if;

    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='locations' and column_name='title'
    ) then
      execute 'update public.locations set name = nullif(btrim(title::text),'''') where name is null';
    end if;

    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='locations' and column_name='coordinates'
    ) then
      execute format(
        'update public.locations set position = coordinates::%I.geography where position is null and coordinates is not null',
        postgis_schema
      );
    end if;
  end if;
end
$locations$;

-- Canonical owner FK, NOT VALID so historical orphan records never get deleted.
do $locations_owner_fk$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.locations'::regclass
      and conname='locations_owner_id_fkey'
  ) then
    alter table public.locations
      add constraint locations_owner_id_fkey
      foreign key (owner_id) references public.profiles(id)
      on delete cascade not valid;
  end if;
end
$locations_owner_fk$;

create index if not exists locations_owner_canonical_idx
  on public.locations(owner_id, created_at desc);
create index if not exists locations_status_visibility_idx
  on public.locations(status, visibility, created_at desc);
create index if not exists locations_position_canonical_gix
  on public.locations using gist(position);

-- --------------------------------------------------------------------------
-- LOCATION SOCIAL TABLES
-- --------------------------------------------------------------------------
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  icon text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.location_categories (
  location_id uuid not null references public.locations(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(location_id, category_id)
);

create table if not exists public.location_photos (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  caption text not null default '',
  sort_order smallint not null default 0,
  status public.social_content_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.location_tags (
  location_id uuid not null references public.locations(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(location_id, tag_id)
);

-- --------------------------------------------------------------------------
-- COMMENTS: add canonical columns to existing legacy comments without deletion.
-- --------------------------------------------------------------------------
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id) on delete cascade,
  author_id uuid,
  parent_id uuid,
  body text,
  rating smallint,
  status public.social_content_status not null default 'visible',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.comments add column if not exists author_id uuid;
alter table public.comments add column if not exists parent_id uuid;
alter table public.comments add column if not exists body text;
alter table public.comments add column if not exists rating smallint;
alter table public.comments add column if not exists status public.social_content_status default 'visible';
alter table public.comments add column if not exists created_at timestamptz default now();
alter table public.comments add column if not exists updated_at timestamptz default now();

-- Backfill canonical author/body from common legacy aliases when they exist.
do $comments_backfill$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='comments' and column_name='user_id'
  ) then
    execute $q$
      update public.comments
      set author_id = user_id::uuid
      where author_id is null
        and user_id is not null
        and user_id::text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    $q$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='comments' and column_name='comment'
  ) then
    execute 'update public.comments set body = comment::text where body is null and comment is not null';
  elsif exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='comments' and column_name='text'
  ) then
    execute 'update public.comments set body = text::text where body is null and text is not null';
  end if;
end
$comments_backfill$;

-- Add canonical comment constraints as NOT VALID where legacy rows may be dirty.
do $comments_constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.comments'::regclass
      and conname='comments_author_id_fkey'
  ) then
    alter table public.comments
      add constraint comments_author_id_fkey
      foreign key(author_id) references public.profiles(id)
      on delete cascade not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.comments'::regclass
      and conname='comments_parent_id_fkey'
  ) then
    alter table public.comments
      add constraint comments_parent_id_fkey
      foreign key(parent_id) references public.comments(id)
      on delete cascade not valid;
  end if;
end
$comments_constraints$;

create index if not exists comments_location_canonical_idx
  on public.comments(location_id, created_at desc);
create index if not exists comments_author_canonical_idx
  on public.comments(author_id, created_at desc);

-- --------------------------------------------------------------------------
-- INVITES / CHECK-INS / NOTIFICATIONS
-- --------------------------------------------------------------------------
create table if not exists public.invites (
  code text primary key,
  created_by uuid references public.profiles(id),
  max_uses integer not null default 1,
  uses integer not null default 0,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.invite_redemptions (
  code text not null references public.invites(code),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key(code, user_id)
);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id, following_id),
  check(follower_id <> following_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);
create index if not exists notifications_user_unread_idx
  on public.notifications(user_id, created_at desc) where not is_read;

-- PostGIS schema may be public or extensions.
do $check_ins$
declare
  postgis_schema text;
begin
  select n.nspname into postgis_schema
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace
  where e.extname='postgis';

  if to_regclass('public.check_ins') is null then
    execute format($ddl$
      create table public.check_ins (
        id uuid primary key default gen_random_uuid(),
        user_id uuid not null references public.profiles(id) on delete cascade,
        location_id uuid not null references public.locations(id) on delete cascade,
        position %I.geography(Point,4326) not null,
        accuracy_m numeric not null,
        created_at timestamptz not null default now()
      )
    $ddl$, postgis_schema);
  end if;
end
$check_ins$;
create index if not exists check_ins_user_canonical_idx
  on public.check_ins(user_id, created_at desc);
create index if not exists check_ins_location_canonical_idx
  on public.check_ins(location_id, created_at desc);

-- Ensure achievement table exists in canonical form.
create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_key text not null,
  unlocked_at timestamptz not null default now(),
  unique(user_id, achievement_key)
);

-- --------------------------------------------------------------------------
-- AUTH / SERVER-MANAGED ACTOR TRIGGERS
-- --------------------------------------------------------------------------
create or replace function public.handle_new_auth_user_compat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate text;
  user_id_type text;
  display_value text;
begin
  candidate := 'explorer_' || substr(replace(new.id::text,'-',''),1,12);
  display_value := coalesce(
    nullif(new.raw_user_meta_data->>'full_name',''),
    nullif(split_part(coalesce(new.email,''),'@',1),''),
    'Дослідник'
  );

  select data_type into user_id_type
  from information_schema.columns
  where table_schema='public' and table_name='profiles' and column_name='user_id';

  if user_id_type='uuid' then
    execute $q$
      insert into public.profiles(id,user_id,username,name,display_name,avatar_url)
      values($1,$1,$2,$3,$3,$4)
      on conflict(id) do nothing
    $q$ using new.id,candidate,display_value,new.raw_user_meta_data->>'avatar_url';
  elsif user_id_type is not null then
    execute $q$
      insert into public.profiles(id,user_id,username,name,display_name,avatar_url)
      values($1,$1::text,$2,$3,$3,$4)
      on conflict(id) do nothing
    $q$ using new.id,candidate,display_value,new.raw_user_meta_data->>'avatar_url';
  else
    insert into public.profiles(id,username,name,display_name,avatar_url)
    values(new.id,candidate,display_value,display_value,new.raw_user_meta_data->>'avatar_url')
    on conflict(id) do nothing;
  end if;

  insert into public.user_settings(user_id)
  values(new.id)
  on conflict(user_id) do nothing;

  return new;
end
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user_compat();

create or replace function public.set_comment_actor_compat()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if tg_op='INSERT' then
    new.author_id := auth.uid();
    new.status := 'visible';
    new.created_at := coalesce(new.created_at, now());
  elsif new.author_id is distinct from old.author_id
     or new.created_at is distinct from old.created_at
     or new.status is distinct from old.status then
    raise exception 'comment system fields are server-managed' using errcode='42501';
  end if;

  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists comments_actor_compat on public.comments;
create trigger comments_actor_compat
before insert or update on public.comments
for each row execute function public.set_comment_actor_compat();

create or replace function public.set_photo_actor_compat()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if tg_op='INSERT' then
    new.uploader_id := auth.uid();
    new.status := 'pending';
    new.created_at := coalesce(new.created_at, now());
  elsif new.uploader_id is distinct from old.uploader_id
     or new.created_at is distinct from old.created_at
     or new.status is distinct from old.status then
    raise exception 'photo system fields are server-managed' using errcode='42501';
  end if;

  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists location_photos_actor_compat on public.location_photos;
create trigger location_photos_actor_compat
before insert or update on public.location_photos
for each row execute function public.set_photo_actor_compat();

create or replace function public.set_follow_actor_compat()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  new.follower_id := auth.uid();
  new.created_at := now();
  return new;
end
$$;

drop trigger if exists follows_set_actor on public.follows;
drop trigger if exists follows_set_actor_compat on public.follows;
create trigger follows_set_actor_compat
before insert on public.follows
for each row execute function public.set_follow_actor_compat();

-- --------------------------------------------------------------------------
-- REQUIRED RPCs
-- --------------------------------------------------------------------------
create or replace function public.redeem_invite(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  invitation public.invites%rowtype;
begin
  if uid is null then raise exception 'authentication required'; end if;

  select * into invitation
  from public.invites
  where code=upper(btrim(p_code))
    and uses < max_uses
    and (expires_at is null or expires_at > now())
  for update;

  if invitation.code is null then
    raise exception 'invalid or expired invite';
  end if;

  insert into public.invite_redemptions(code,user_id)
  values(invitation.code,uid)
  on conflict(user_id) do nothing;

  if not found then
    raise exception 'invite already redeemed';
  end if;

  update public.invites
  set uses=uses+1
  where code=invitation.code;

  update public.profiles
  set invite_redeemed=true,
      invited_by=invitation.created_by
  where id=uid;
end
$$;

create or replace function public.create_invite()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  generated text;
begin
  if uid is null then raise exception 'authentication required'; end if;

  update public.profiles
  set invite_balance = greatest(coalesce(invite_balance,0)-1,0)
  where id=uid
    and invite_redeemed is true
    and coalesce(invite_balance,0)>0;

  if not found then
    raise exception 'invite balance exhausted';
  end if;

  loop
    generated := upper(substr(md5(uid::text||clock_timestamp()::text||random()::text),1,10));
    begin
      insert into public.invites(code,created_by,max_uses)
      values(generated,uid,1);
      exit;
    exception when unique_violation then
      -- Extremely unlikely code collision: generate again.
    end;
  end loop;

  return generated;
end
$$;

create or replace function public.create_check_in(
  target_location_id uuid,
  user_lat float8,
  user_lng float8,
  gps_accuracy_m float8
)
returns jsonb
language plpgsql
security definer
set search_path='extensions','public','pg_catalog'
as $$
declare
  uid uuid := auth.uid();
  target geography;
  check_in_id uuid;
  awarded integer := 20;
  recent_count integer;
begin
  if uid is null then raise exception 'authentication required'; end if;
  if user_lat not between -90 and 90 or user_lng not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  if gps_accuracy_m is null or gps_accuracy_m < 0 or gps_accuracy_m > 100 then
    raise exception 'GPS accuracy is insufficient';
  end if;

  select position into target
  from public.locations
  where id=target_location_id
    and (owner_id=uid or status='approved');

  if target is null then raise exception 'location unavailable'; end if;

  if st_distance(
       target,
       st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography
     ) > 100 then
    raise exception 'must be within 100 meters';
  end if;

  select count(*) into recent_count
  from public.check_ins
  where user_id=uid
    and location_id=target_location_id
    and created_at > now() - interval '30 minutes';

  if recent_count > 0 then
    raise exception 'check-in recently recorded';
  end if;

  insert into public.check_ins(user_id,location_id,position,accuracy_m)
  values(
    uid,
    target_location_id,
    st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography,
    gps_accuracy_m
  )
  returning id into check_in_id;

  update public.profiles set xp=coalesce(xp,0)+awarded where id=uid;

  return jsonb_build_object('check_in_id',check_in_id,'xp_awarded',awarded);
end
$$;

-- Keep the 6-argument overload used by current Flutter code authoritative.
create or replace function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude float8,
  location_longitude float8,
  p_image_url text default null,
  p_category text default 'general'
)
returns uuid
language plpgsql
security definer
set search_path='extensions','public','pg_catalog'
as $$
declare
  uid uuid := auth.uid();
  location_id uuid;
  normalized_category text := coalesce(nullif(btrim(p_category),''),'general');
begin
  if uid is null then raise exception 'authentication required'; end if;
  if nullif(btrim(location_title),'') is null then raise exception 'title required'; end if;
  if location_latitude not between -90 and 90 or location_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;

  insert into public.locations(
    owner_id,name,description,position,status,visibility,
    moderation,secrecy,category,image_url
  ) values (
    uid,btrim(location_title),coalesce(btrim(location_description),''),
    st_setsrid(st_makepoint(location_longitude,location_latitude),4326)::geography,
    'draft','public','draft','public',normalized_category,nullif(btrim(p_image_url),'')
  )
  returning id into location_id;

  update public.profiles set xp=coalesce(xp,0)+10 where id=uid;
  return location_id;
end
$$;

create or replace function public.update_own_location(
  p_location_id uuid,
  p_title text,
  p_description text,
  p_category text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  update public.locations
  set name=btrim(p_title),
      description=coalesce(btrim(p_description),''),
      category=coalesce(nullif(btrim(p_category),''),'general'),
      updated_at=now()
  where id=p_location_id
    and owner_id=auth.uid()
    and status in ('draft','rejected');

  if not found then
    raise exception 'location not found or access denied';
  end if;
end
$$;

create or replace function public.check_and_unlock_achievements()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  location_count integer := 0;
  photo_count integer := 0;
  friend_count integer := 0;
  distance_km numeric := 0;
begin
  if uid is null then raise exception 'authentication required'; end if;

  select count(*) into location_count
  from public.locations where owner_id=uid;

  select count(*) into photo_count
  from public.location_photos where uploader_id=uid;

  if to_regclass('public.friendships') is not null then
    execute $q$
      select count(*) from public.friendships
      where status='accepted' and (user_id_1=$1 or user_id_2=$1)
    $q$ into friend_count using uid;
  end if;

  select coalesce(distance_traveled_km,0)
  into distance_km from public.profiles where id=uid;

  if location_count>=1 then
    insert into public.user_achievements(user_id,achievement_key)
    values(uid,'first_location') on conflict do nothing;
  end if;
  if friend_count>=10 then
    insert into public.user_achievements(user_id,achievement_key)
    values(uid,'ten_friends') on conflict do nothing;
  end if;
  if photo_count>=10 then
    insert into public.user_achievements(user_id,achievement_key)
    values(uid,'photo_collector') on conflict do nothing;
  end if;
  if distance_km>=100 then
    insert into public.user_achievements(user_id,achievement_key)
    values(uid,'explorer_100km') on conflict do nothing;
  end if;
end
$$;

-- --------------------------------------------------------------------------
-- NOTIFICATION TRIGGERS
-- --------------------------------------------------------------------------
create or replace function public.notify_user_about_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  follower_name text;
begin
  select coalesce(nullif(p.display_name,''),p.username,'Мандрівник')
  into follower_name from public.profiles p where p.id=new.follower_id;

  insert into public.notifications(user_id,title,message)
  values(
    new.following_id,
    'Новий підписник',
    left(coalesce(follower_name,'Мандрівник'),100)||' підписався на ваш профіль.'
  );
  return new;
end
$$;

drop trigger if exists follows_notify_user on public.follows;
create trigger follows_notify_user
after insert on public.follows
for each row execute function public.notify_user_about_follow();

create or replace function public.notify_location_owner_about_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner uuid;
  location_name text;
begin
  select l.owner_id,l.name into location_owner,location_name
  from public.locations l where l.id=new.location_id;

  if location_owner is null or location_owner=new.author_id then
    return new;
  end if;

  insert into public.notifications(user_id,title,message)
  values(
    location_owner,
    'Новий коментар',
    'До локації «'||left(coalesce(location_name,'Без назви'),100)||'» додано новий коментар.'
  );
  return new;
end
$$;

drop trigger if exists comments_notify_location_owner on public.comments;
create trigger comments_notify_location_owner
after insert on public.comments
for each row execute function public.notify_location_owner_about_comment();

-- --------------------------------------------------------------------------
-- RLS: replace only policies on canonical user-facing tables.
-- --------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.locations enable row level security;
alter table public.categories enable row level security;
alter table public.location_categories enable row level security;
alter table public.location_photos enable row level security;
alter table public.tags enable row level security;
alter table public.location_tags enable row level security;
alter table public.comments enable row level security;
alter table public.invites enable row level security;
alter table public.invite_redemptions enable row level security;
alter table public.check_ins enable row level security;
alter table public.follows enable row level security;
alter table public.notifications enable row level security;
alter table public.user_achievements enable row level security;

do $drop_policies$
declare
  t text;
  p record;
begin
  foreach t in array array[
    'profiles','user_settings','locations','categories','location_categories',
    'location_photos','tags','location_tags','comments','invites','invite_redemptions',
    'check_ins','follows','notifications','user_achievements'
  ] loop
    for p in
      select policyname from pg_policies
      where schemaname='public' and tablename=t
    loop
      execute format('drop policy if exists %I on public.%I',p.policyname,t);
    end loop;
  end loop;
end
$drop_policies$;

create policy profiles_read on public.profiles
for select to authenticated using(true);
create policy profiles_update_self on public.profiles
for update to authenticated
using(id=auth.uid()) with check(id=auth.uid());

create policy user_settings_self on public.user_settings
for all to authenticated
using(user_id=auth.uid()) with check(user_id=auth.uid());

create policy locations_read on public.locations
for select to authenticated using(
  owner_id=auth.uid() or (status='approved' and visibility in ('public','unlisted'))
);
create policy locations_insert on public.locations
for insert to authenticated with check(owner_id=auth.uid() and status='draft');
create policy locations_update on public.locations
for update to authenticated
using(owner_id=auth.uid() and status in ('draft','rejected'))
with check(owner_id=auth.uid() and status in ('draft','rejected'));
create policy locations_delete on public.locations
for delete to authenticated
using(owner_id=auth.uid() and status in ('draft','rejected'));

create policy categories_read on public.categories
for select to authenticated using(is_active);

create policy location_categories_read on public.location_categories
for select to authenticated using(true);
create policy location_categories_owner_insert on public.location_categories
for insert to authenticated with check(
  exists(select 1 from public.locations l where l.id=location_id and l.owner_id=auth.uid())
);
create policy location_categories_owner_delete on public.location_categories
for delete to authenticated using(
  exists(select 1 from public.locations l where l.id=location_id and l.owner_id=auth.uid())
);

create policy location_photos_read on public.location_photos
for select to authenticated using(
  uploader_id=auth.uid()
  or status='visible'
);
create policy location_photos_owner_insert on public.location_photos
for insert to authenticated with check(
  uploader_id=auth.uid()
  and exists(select 1 from public.locations l where l.id=location_id and l.owner_id=auth.uid())
);
create policy location_photos_owner_update on public.location_photos
for update to authenticated
using(uploader_id=auth.uid()) with check(uploader_id=auth.uid());
create policy location_photos_owner_delete on public.location_photos
for delete to authenticated using(uploader_id=auth.uid());

create policy tags_read on public.tags
for select to authenticated using(true);
create policy location_tags_read on public.location_tags
for select to authenticated using(true);

create policy comments_read on public.comments
for select to authenticated using(
  author_id=auth.uid()
  or (
    status='visible'
    and exists(
      select 1 from public.locations l
      where l.id=location_id
        and (l.owner_id=auth.uid() or (l.status='approved' and l.visibility in ('public','unlisted')))
    )
  )
);
create policy comments_insert on public.comments
for insert to authenticated with check(
  author_id=auth.uid()
  and status='visible'
  and exists(
    select 1 from public.locations l
    where l.id=location_id
      and (l.owner_id=auth.uid() or (l.status='approved' and l.visibility in ('public','unlisted')))
  )
);
create policy comments_update on public.comments
for update to authenticated
using(author_id=auth.uid()) with check(author_id=auth.uid());
create policy comments_delete on public.comments
for delete to authenticated using(author_id=auth.uid());

-- Invites are intentionally RPC-only: no direct client policies.

create policy check_ins_read on public.check_ins
for select to authenticated using(user_id=auth.uid());

create policy follows_read on public.follows
for select to authenticated using(true);
create policy follows_insert on public.follows
for insert to authenticated with check(follower_id=auth.uid());
create policy follows_delete on public.follows
for delete to authenticated using(follower_id=auth.uid());

create policy notifications_read on public.notifications
for select to authenticated using(user_id=auth.uid());
create policy notifications_update on public.notifications
for update to authenticated
using(user_id=auth.uid()) with check(user_id=auth.uid());

create policy achievements_read on public.user_achievements
for select to authenticated using(user_id=auth.uid());

-- --------------------------------------------------------------------------
-- PRIVILEGES: client cannot write server-managed fields directly.
-- --------------------------------------------------------------------------
revoke all on public.profiles from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(username,name,display_name,avatar_url) on public.profiles to authenticated;

revoke all on public.locations from anon,authenticated;
grant select on public.locations to authenticated;
grant insert(name,description,position,visibility,category,image_url,road_difficulty,has_parking,safety)
  on public.locations to authenticated;
grant update(name,description,position,visibility,category,image_url,road_difficulty,has_parking,safety)
  on public.locations to authenticated;
grant delete on public.locations to authenticated;

revoke all on public.user_settings from anon,authenticated;
grant select,insert,update,delete on public.user_settings to authenticated;

revoke all on public.categories from anon,authenticated;
grant select on public.categories to authenticated;

revoke all on public.location_categories from anon,authenticated;
grant select on public.location_categories to authenticated;
grant insert(location_id,category_id) on public.location_categories to authenticated;
grant delete on public.location_categories to authenticated;

revoke all on public.location_photos from anon,authenticated;
grant select on public.location_photos to authenticated;
grant insert(location_id,storage_path,caption,sort_order) on public.location_photos to authenticated;
grant update(caption,sort_order) on public.location_photos to authenticated;
grant delete on public.location_photos to authenticated;

revoke all on public.tags from anon,authenticated;
grant select on public.tags to authenticated;
revoke all on public.location_tags from anon,authenticated;
grant select on public.location_tags to authenticated;

revoke all on public.comments from anon,authenticated;
grant select on public.comments to authenticated;
grant insert(location_id,parent_id,body,rating) on public.comments to authenticated;
grant update(body,rating) on public.comments to authenticated;
grant delete on public.comments to authenticated;

revoke all on public.invites from anon,authenticated;
revoke all on public.invite_redemptions from anon,authenticated;

revoke all on public.check_ins from anon,authenticated;
grant select on public.check_ins to authenticated;

revoke all on public.follows from anon,authenticated;
grant select on public.follows to authenticated;
grant insert(following_id) on public.follows to authenticated;
grant delete on public.follows to authenticated;

revoke all on public.notifications from anon,authenticated;
grant select on public.notifications to authenticated;
grant update(is_read) on public.notifications to authenticated;

revoke all on public.user_achievements from anon,authenticated;
grant select on public.user_achievements to authenticated;

revoke all on function public.redeem_invite(text) from public;
revoke all on function public.create_invite() from public;
revoke all on function public.create_check_in(uuid,float8,float8,float8) from public;
revoke all on function public.create_location_with_xp(text,text,float8,float8,text,text) from public;
revoke all on function public.update_own_location(uuid,text,text,text) from public;
revoke all on function public.check_and_unlock_achievements() from public;

grant execute on function public.redeem_invite(text) to authenticated;
grant execute on function public.create_invite() to authenticated;
grant execute on function public.create_check_in(uuid,float8,float8,float8) to authenticated;
grant execute on function public.create_location_with_xp(text,text,float8,float8,text,text) to authenticated;
grant execute on function public.update_own_location(uuid,text,text,text) to authenticated;
grant execute on function public.check_and_unlock_achievements() to authenticated;

-- --------------------------------------------------------------------------
-- STORAGE
-- --------------------------------------------------------------------------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'location_images',
  'location_images',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict(id) do update
set file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists location_images_public_read on storage.objects;
drop policy if exists location_images_authenticated_upload on storage.objects;
drop policy if exists location_images_owner_delete on storage.objects;

create policy location_images_public_read
on storage.objects for select to public
using(bucket_id='location_images');

create policy location_images_authenticated_upload
on storage.objects for insert to authenticated
with check(
  bucket_id='location_images'
  and (storage.foldername(name))[1]=auth.uid()::text
);

create policy location_images_owner_delete
on storage.objects for delete to authenticated
using(
  bucket_id='location_images'
  and (storage.foldername(name))[1]=auth.uid()::text
);

-- Realtime notifications only, if publication exists and table isn't included.
do $realtime$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end
$realtime$;

commit;
