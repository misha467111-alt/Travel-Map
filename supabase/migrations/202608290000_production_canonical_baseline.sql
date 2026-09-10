-- Canonical factual production baseline. SECURITY HARDENING REQUIRED AFTER BASELINE.

set check_function_bodies = off;

create schema if not exists extensions;

create extension if not exists postgis with schema public;

create extension if not exists pgcrypto with schema extensions;

create extension if not exists "uuid-ossp" with schema extensions;

create type public.location_status as enum ('draft', 'pending', 'approved', 'rejected', 'archived');

create type public.location_visibility as enum ('public', 'unlisted', 'secret', 'private');

create type public.social_content_status as enum ('pending', 'visible', 'hidden', 'deleted');

create table public.achievement_definitions (achievement_key text not null, name text not null, description text not null, icon text not null, category text not null, metric text not null, target numeric not null, sort_order integer default 0 not null, created_at timestamp with time zone default now() not null);

create table public.categories (id uuid default gen_random_uuid() not null, slug text not null, name text not null, icon text default ''::text not null, is_active boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);

create table public.check_ins (id uuid default gen_random_uuid() not null, user_id uuid not null, location_id uuid not null, "position" geography(Point,4326) not null, accuracy_m numeric not null, created_at timestamp with time zone default now() not null);

create table public.comments (id uuid default gen_random_uuid() not null, location_id uuid not null, user_id uuid not null, text text not null, rating integer, created_at timestamp with time zone default timezone('utc'::text, now()) not null, author_id uuid, parent_id uuid, body text, status social_content_status default 'visible'::social_content_status, updated_at timestamp with time zone default now());

create table public.follows (follower_id uuid not null, following_id uuid not null, created_at timestamp with time zone default now() not null);

create table public.friendships (id uuid default gen_random_uuid() not null, user_id_1 uuid not null, user_id_2 uuid not null, status text not null, created_at timestamp with time zone default timezone('utc'::text, now()) not null);

create table public.invite_codes (code text not null, created_by text, created_at timestamp with time zone default now());

create table public.invite_redemptions (code text not null, user_id uuid not null, redeemed_at timestamp with time zone default now() not null);

create table public.invites (code text not null, created_by uuid, max_uses integer default 1 not null, uses integer default 0 not null, expires_at timestamp with time zone, created_at timestamp with time zone default now() not null);

create table public.location_categories (location_id uuid not null, category_id uuid not null, added_by uuid, created_at timestamp with time zone default now() not null);

create table public.location_photos (id uuid default gen_random_uuid() not null, location_id uuid not null, uploader_id uuid not null, storage_path text not null, caption text default ''::text not null, sort_order smallint default 0 not null, status social_content_status default 'pending'::social_content_status not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);

create table public.location_tags (location_id uuid not null, tag_id uuid not null, added_by uuid, created_at timestamp with time zone default now() not null);

create table public.locations (id uuid default gen_random_uuid() not null, user_id uuid not null, title text not null, description text default ''::text not null, coordinates geography(Point,4326) not null, created_at timestamp with time zone default timezone('utc'::text, now()) not null, image_url text, category text default 'general'::text, is_public boolean default true not null, owner_id uuid not null, name text not null, "position" geography(Point,4326) not null, status location_status default 'draft'::location_status not null, visibility location_visibility default 'public'::location_visibility not null, moderation text default 'draft'::text not null, secrecy text default 'public'::text not null, road_difficulty text default 'easy'::text, has_parking boolean default false, safety text default 'unknown'::text, minimum_xp integer default 0, rating numeric(3,2) default 0, ratings_count integer default 0, updated_at timestamp with time zone default now(), request_id uuid);

create table public.messages (id text default (gen_random_uuid())::text not null, sender_id text, receiver_id text, text text, "timestamp" timestamp with time zone default now());

create table public.notifications (id uuid default gen_random_uuid() not null, user_id uuid not null, title text not null, message text not null, is_read boolean default false not null, created_at timestamp with time zone default now() not null);

create table public.profiles (id uuid default gen_random_uuid() not null, user_id uuid not null, name text default 'Дослідник'::text not null, xp integer default 0 not null, level text default 'Новачок'::text not null, invites_left integer default 3, is_developer boolean default false, created_at timestamp with time zone default timezone('utc'::text, now()) not null, distance_traveled_km numeric default 0 not null, username text not null, display_name text default ''::text not null, avatar_url text, updated_at timestamp with time zone default now() not null, invite_redeemed boolean default false, invited_by uuid, invite_balance integer default 1, highest_level_rewarded integer default 1 not null);

create table public.reviews (id uuid default gen_random_uuid() not null, location_id uuid not null, user_id uuid not null, text text not null, rating integer, created_at timestamp with time zone default timezone('utc'::text, now()) not null);

create table public.routes (id text not null, title text, description text, author text, author_id text, points jsonb default '[]'::jsonb, liked_by_users text[] default '{}'::text[]);

create table public.tags (id uuid default gen_random_uuid() not null, slug text not null, name text not null, created_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);

create table public.user_achievements (id uuid default gen_random_uuid() not null, user_id uuid not null, achievement_key text not null, unlocked_at timestamp with time zone default now() not null);

create table public.user_settings (user_id uuid not null, locale text default 'uk'::text not null, theme text default 'system'::text not null, distance_unit text default 'metric'::text not null, notifications_enabled boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);

alter table public.achievement_definitions add constraint achievement_definitions_pkey PRIMARY KEY (achievement_key);

alter table public.achievement_definitions add constraint achievement_definitions_target_check CHECK (target > 0::numeric);

alter table public.categories add constraint categories_pkey PRIMARY KEY (id);

alter table public.categories add constraint categories_slug_key UNIQUE (slug);

alter table public.check_ins add constraint check_ins_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;

alter table public.check_ins add constraint check_ins_pkey PRIMARY KEY (id);

alter table public.check_ins add constraint check_ins_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.comments add constraint comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE NOT VALID;

alter table public.comments add constraint comments_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;

alter table public.comments add constraint comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES comments(id) ON DELETE CASCADE NOT VALID;

alter table public.comments add constraint comments_pkey PRIMARY KEY (id);

alter table public.comments add constraint comments_rating_check CHECK (rating >= 1 AND rating <= 5);

alter table public.comments add constraint comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public.follows add constraint follows_check CHECK (follower_id <> following_id);

alter table public.follows add constraint follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.follows add constraint follows_following_id_fkey FOREIGN KEY (following_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.follows add constraint follows_pkey PRIMARY KEY (follower_id, following_id);

alter table public.friendships add constraint check_not_self CHECK (user_id_1 <> user_id_2);

alter table public.friendships add constraint friendships_pkey PRIMARY KEY (id);

alter table public.friendships add constraint friendships_status_check CHECK (status = ANY (ARRAY['pending'::text, 'accepted'::text]));

alter table public.friendships add constraint friendships_user_id_1_fkey FOREIGN KEY (user_id_1) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public.friendships add constraint friendships_user_id_2_fkey FOREIGN KEY (user_id_2) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public.invite_codes add constraint invite_codes_pkey PRIMARY KEY (code);

alter table public.invite_redemptions add constraint invite_redemptions_code_fkey FOREIGN KEY (code) REFERENCES invites(code);

alter table public.invite_redemptions add constraint invite_redemptions_pkey PRIMARY KEY (code, user_id);

alter table public.invite_redemptions add constraint invite_redemptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.invite_redemptions add constraint invite_redemptions_user_id_key UNIQUE (user_id);

alter table public.invites add constraint invites_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);

alter table public.invites add constraint invites_pkey PRIMARY KEY (code);

alter table public.location_categories add constraint location_categories_added_by_fkey FOREIGN KEY (added_by) REFERENCES profiles(id) ON DELETE SET NULL;

alter table public.location_categories add constraint location_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE;

alter table public.location_categories add constraint location_categories_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;

alter table public.location_categories add constraint location_categories_pkey PRIMARY KEY (location_id, category_id);

alter table public.location_photos add constraint location_photos_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;

alter table public.location_photos add constraint location_photos_pkey PRIMARY KEY (id);

alter table public.location_photos add constraint location_photos_storage_path_key UNIQUE (storage_path);

alter table public.location_photos add constraint location_photos_uploader_id_fkey FOREIGN KEY (uploader_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.location_tags add constraint location_tags_added_by_fkey FOREIGN KEY (added_by) REFERENCES profiles(id) ON DELETE SET NULL;

alter table public.location_tags add constraint location_tags_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;

alter table public.location_tags add constraint location_tags_pkey PRIMARY KEY (location_id, tag_id);

alter table public.location_tags add constraint location_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE;

alter table public.locations add constraint locations_category_check CHECK (category = ANY (ARRAY['general'::text, 'cafe'::text, 'nature'::text, 'culture'::text, 'entertainment'::text]));

alter table public.locations add constraint locations_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE NOT VALID;

alter table public.locations add constraint locations_pkey PRIMARY KEY (id);

alter table public.locations add constraint locations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public.messages add constraint messages_pkey PRIMARY KEY (id);

alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);

alter table public.notifications add constraint notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.profiles add constraint profiles_distance_traveled_km_check CHECK (distance_traveled_km >= 0::numeric);

alter table public.profiles add constraint profiles_identity_columns_match_check CHECK (user_id = id) NOT VALID;

alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);

alter table public.profiles add constraint profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;

alter table public.profiles add constraint profiles_username_length_check CHECK (char_length(username) >= 3 AND char_length(username) <= 30) NOT VALID;

alter table public.profiles add constraint profiles_xp_nonnegative_check CHECK (xp >= 0) NOT VALID;

alter table public.reviews add constraint reviews_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;

alter table public.reviews add constraint reviews_pkey PRIMARY KEY (id);

alter table public.reviews add constraint reviews_rating_check CHECK (rating >= 1 AND rating <= 5);

alter table public.reviews add constraint reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public.routes add constraint routes_pkey PRIMARY KEY (id);

alter table public.tags add constraint tags_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.tags add constraint tags_pkey PRIMARY KEY (id);

alter table public.tags add constraint tags_slug_key UNIQUE (slug);

alter table public.user_achievements add constraint user_achievements_pkey PRIMARY KEY (id);

alter table public.user_achievements add constraint user_achievements_user_id_achievement_key_key UNIQUE (user_id, achievement_key);

alter table public.user_achievements add constraint user_achievements_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

alter table public.user_settings add constraint user_settings_distance_unit_check CHECK (distance_unit = ANY (ARRAY['metric'::text, 'imperial'::text]));

alter table public.user_settings add constraint user_settings_locale_check CHECK (char_length(locale) >= 2 AND char_length(locale) <= 16);

alter table public.user_settings add constraint user_settings_pkey PRIMARY KEY (user_id);

alter table public.user_settings add constraint user_settings_theme_check CHECK (theme = ANY (ARRAY['system'::text, 'light'::text, 'dark'::text]));

alter table public.user_settings add constraint user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX check_ins_location_canonical_idx ON public.check_ins USING btree (location_id, created_at DESC);

CREATE INDEX check_ins_user_canonical_idx ON public.check_ins USING btree (user_id, created_at DESC);

CREATE INDEX comments_author_canonical_idx ON public.comments USING btree (author_id, created_at DESC);

CREATE INDEX comments_location_canonical_idx ON public.comments USING btree (location_id, created_at DESC);

CREATE INDEX follows_follower_created_idx ON public.follows USING btree (follower_id, created_at DESC);

CREATE INDEX follows_following_idx ON public.follows USING btree (following_id, created_at DESC);

CREATE UNIQUE INDEX friendships_unique_idx ON public.friendships USING btree (LEAST(user_id_1, user_id_2), GREATEST(user_id_1, user_id_2));

CREATE INDEX locations_category_idx ON public.locations USING btree (category);

CREATE INDEX locations_owner_canonical_idx ON public.locations USING btree (owner_id, created_at DESC);

CREATE INDEX locations_owner_idx ON public.locations USING btree (owner_id, created_at DESC);

CREATE UNIQUE INDEX locations_owner_request_id_uidx ON public.locations USING btree (owner_id, request_id) WHERE (request_id IS NOT NULL);

CREATE INDEX locations_position_canonical_gix ON public.locations USING gist ("position");

CREATE INDEX locations_position_gist_idx ON public.locations USING gist ("position");

CREATE INDEX locations_public_feed_idx ON public.locations USING btree (status, visibility, created_at DESC);

CREATE INDEX locations_status_visibility_idx ON public.locations USING btree (status, visibility, created_at DESC);

CREATE INDEX messages_sender_recipient_created_idx ON public.messages USING btree (sender_id, receiver_id, "timestamp" DESC);

CREATE INDEX notifications_user_created_idx ON public.notifications USING btree (user_id, created_at DESC);

CREATE INDEX notifications_user_unread_idx ON public.notifications USING btree (user_id, created_at DESC) WHERE (NOT is_read);

CREATE UNIQUE INDEX profiles_user_id_key ON public.profiles USING btree (user_id);

CREATE UNIQUE INDEX profiles_username_key ON public.profiles USING btree (username);

CREATE INDEX reviews_location_created_idx ON public.reviews USING btree (location_id, created_at DESC);

CREATE INDEX user_achievements_user_idx ON public.user_achievements USING btree (user_id, unlocked_at DESC);

CREATE OR REPLACE FUNCTION public.achievement_metric_value(p_uid uuid, p_metric text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  value numeric := 0;
begin
  case p_metric
    when 'locations' then
      if exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='locations' and column_name='owner_id'
      ) then
        execute 'select count(*)::numeric from public.locations where owner_id = $1'
          into value using p_uid;
      elsif exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='locations' and column_name='user_id'
      ) then
        execute 'select count(*)::numeric from public.locations where user_id = $1'
          into value using p_uid;
      end if;

    when 'checkins' then
      if to_regclass('public.check_ins') is not null then
        execute 'select count(*)::numeric from public.check_ins where user_id = $1'
          into value using p_uid;
      end if;

    when 'friends' then
      if to_regclass('public.friendships') is not null then
        execute $q$
          select count(*)::numeric from public.friendships
          where status = 'accepted' and (user_id_1 = $1 or user_id_2 = $1)
        $q$ into value using p_uid;
      end if;

    when 'photos' then
      if to_regclass('public.location_photos') is not null then
        execute 'select count(*)::numeric from public.location_photos where uploader_id = $1'
          into value using p_uid;
      end if;

    when 'comments' then
      if to_regclass('public.comments') is not null then
        if exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name='comments' and column_name='author_id'
        ) then
          execute 'select count(*)::numeric from public.comments where author_id = $1'
            into value using p_uid;
        elsif exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name='comments' and column_name='user_id'
        ) then
          execute 'select count(*)::numeric from public.comments where user_id::text = $1::text'
            into value using p_uid;
        end if;
      end if;

    when 'distance' then
      select coalesce(distance_traveled_km, 0)::numeric
      into value
      from public.profiles
      where id = p_uid;

    when 'xp' then
      select coalesce(xp, 0)::numeric
      into value
      from public.profiles
      where id = p_uid;

    else
      value := 0;
  end case;

  return coalesce(value, 0);
end
$function$
;

CREATE OR REPLACE FUNCTION public.award_invite_for_level_unlock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  new_tier integer;
  rewarded integer;
  gained integer;
begin
  new.xp := greatest(coalesce(new.xp, 0), 0);
  new_tier := public.travel_level_tier(new.xp);
  rewarded := greatest(1, least(5, coalesce(old.highest_level_rewarded, 1)));

  if new_tier > rewarded then
    gained := new_tier - rewarded;
    new.invite_balance := greatest(coalesce(new.invite_balance, 0), 0) + gained;
    new.highest_level_rewarded := new_tier;
  else
    new.highest_level_rewarded := rewarded;
  end if;

  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
 RETURNS double precision
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  RETURN ST_Distance(
    ST_SetSRID(ST_MakePoint(lon1, lat1), 4326)::geography,
    ST_SetSRID(ST_MakePoint(lon2, lat2), 4326)::geography
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_and_unlock_achievements()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  d record;
  progress numeric;
begin
  if uid is null then
    raise exception 'authentication required';
  end if;

  for d in
    select achievement_key, metric, target
    from public.achievement_definitions
  loop
    progress := public.achievement_metric_value(uid, d.metric);
    if progress >= d.target then
      insert into public.user_achievements(user_id, achievement_key)
      values (uid, d.achievement_key)
      on conflict (user_id, achievement_key) do nothing;
    end if;
  end loop;
end
$function$
;

CREATE OR REPLACE FUNCTION public.create_check_in(target_location_id uuid, user_lat double precision, user_lng double precision, gps_accuracy_m double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'pg_catalog'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.create_invite()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text DEFAULT NULL::text, p_category text DEFAULT 'general'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'pg_catalog'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'pg_catalog'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_achievement_progress()
 RETURNS TABLE(achievement_key text, name text, description text, icon text, category text, unlock_condition text, progress numeric, target numeric, is_unlocked boolean, unlocked_at timestamp with time zone, sort_order integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'authentication required';
  end if;

  perform public.check_and_unlock_achievements();

  return query
  select
    d.achievement_key,
    d.name,
    d.description,
    d.icon,
    d.category,
    case d.metric
      when 'locations' then 'Додайте ' || d.target::int || ' локацій'
      when 'checkins' then 'Зробіть ' || d.target::int || ' check-in'
      when 'friends' then 'Додайте ' || d.target::int || ' друзів'
      when 'photos' then 'Додайте ' || d.target::int || ' фото'
      when 'comments' then 'Залиште ' || d.target::int || ' коментарів'
      when 'distance' then 'Подолайте ' || d.target::int || ' км'
      when 'xp' then 'Наберіть ' || d.target::int || ' XP'
      else 'Виконайте умову'
    end,
    public.achievement_metric_value(uid, d.metric),
    d.target,
    ua.id is not null,
    ua.unlocked_at,
    d.sort_order
  from public.achievement_definitions d
  left join public.user_achievements ua
    on ua.user_id = uid and ua.achievement_key = d.achievement_key
  order by d.sort_order, d.achievement_key;
end
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  candidate_username text;
  candidate_display_name text;
begin
  candidate_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data ->> 'username', ''),
    '[^a-zA-Z0-9_]+', '', 'g'
  ));

  if char_length(candidate_username) < 3 then
    candidate_username := 'explorer';
  end if;

  candidate_username := left(candidate_username, 17)
    || '_' || substr(replace(new.id::text, '-', ''), 1, 12);

  candidate_display_name := left(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Дослідник'
  ), 80);

  insert into public.profiles (
    id,
    user_id,
    name,
    username,
    display_name,
    avatar_url
  )
  values (
    new.id,
    new.id,
    candidate_display_name,
    candidate_username,
    candidate_display_name,
    nullif(btrim(new.raw_user_meta_data ->> 'avatar_url'), '')
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user_compat()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (user_id, name, xp, level, invites_left, is_developer)
  VALUES (
    new.id::text, 
    COALESCE(new.raw_user_meta_data->>'username', 'Мандрівник'), 
    0,
    'Новачок',
    3, 
    false
  );
  RETURN new;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_location_owner_about_comment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.notify_user_about_follow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.profile_level_for_xp(points integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
  select case
    when points >= 1000 then 'Першовідкривач'
    when points >= 600 then 'Турист'
    when points >= 300 then 'Мандрівник'
    when points >= 100 then 'Дослідник'
    else 'Новачок'
  end
$function$
;

CREATE OR REPLACE FUNCTION public.protect_location_system_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'extensions', 'public', 'pg_catalog'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.redeem_invite(p_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.set_comment_actor_compat()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.set_follow_actor_compat()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  new.follower_id := auth.uid();
  new.created_at := now();
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.set_photo_actor_compat()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.set_profile_server_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.id is null then
    raise exception 'profile id is required';
  end if;

  -- Prevent either client or server code from separating the profile from its
  -- Auth identity. This also supports the legacy `user_id` column.
  new.user_id := new.id;

  if tg_op = 'UPDATE'
     and current_user in ('anon', 'authenticated')
     and (
       new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.xp is distinct from old.xp
       or new.level is distinct from old.level
     ) then
    raise exception 'identity, xp and level are server-managed fields'
      using errcode = '42501';
  end if;

  new.xp := greatest(coalesce(new.xp, 0), 0);
  new.level := public.profile_level_for_xp(new.xp);
  new.updated_at := now();
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.set_user_settings_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.travel_discover_locations(p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_category text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 30)
 RETURNS TABLE(id uuid, user_id uuid, title text, description text, coordinates jsonb, created_at timestamp with time zone, image_url text, category text, status text, visibility text, moderation text, updated_at timestamp with time zone, author_name text, author_avatar_url text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select l.id, l.owner_id, l.name, l.description,
         public.st_asgeojson(l.position::public.geometry)::jsonb,
         l.created_at, l.image_url, l.category, l.status::text,
         l.visibility::text, l.moderation, l.updated_at,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), '??????????'),
         p.avatar_url
    from public.locations l
    left join public.profiles p on p.id = l.owner_id
   where l.status = 'approved'::public.location_status
     and l.visibility = 'public'::public.location_visibility
     and (p_cursor_created_at is null or p_cursor_id is null or
          (l.created_at, l.id) < (p_cursor_created_at, p_cursor_id))
     and (p_category is null or l.category = p_category)
     and (coalesce(trim(p_search), '') = '' or l.name ilike '%' || trim(p_search) || '%')
   order by l.created_at desc, l.id desc
   limit least(greatest(coalesce(p_limit, 30), 1), 40)
$function$
;

CREATE OR REPLACE FUNCTION public.travel_level_tier(points integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
  select case
    when points >= 1000 then 5
    when points >= 600 then 4
    when points >= 300 then 3
    when points >= 100 then 2
    else 1
  end
$function$
;

CREATE OR REPLACE FUNCTION public.travel_locations_in_bounds(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_category text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 300)
 RETURNS TABLE(id uuid, user_id uuid, title text, description text, coordinates jsonb, created_at timestamp with time zone, image_url text, category text, status text, visibility text, moderation text, updated_at timestamp with time zone, author_name text, author_avatar_url text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select l.id, l.owner_id, l.name, l.description,
         public.st_asgeojson(l.position::public.geometry)::jsonb,
         l.created_at, l.image_url, l.category, l.status::text,
         l.visibility::text, l.moderation, l.updated_at,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), '??????????'),
         p.avatar_url
    from public.locations l
    left join public.profiles p on p.id = l.owner_id
   where l.status = 'approved'::public.location_status
     and l.visibility in (
       'public'::public.location_visibility,
       'unlisted'::public.location_visibility
     )
     and l.position operator(public.&&) public.st_makeenvelope(
       least(p_min_lng, p_max_lng), least(p_min_lat, p_max_lat),
       greatest(p_min_lng, p_max_lng), greatest(p_min_lat, p_max_lat), 4326
     )::public.geography
     and (p_category is null or l.category = p_category)
     and (coalesce(trim(p_search), '') = '' or l.name ilike '%' || trim(p_search) || '%')
   order by l.created_at desc, l.id desc
   limit least(greatest(coalesce(p_limit, 300), 1), 500)
$function$
;

CREATE OR REPLACE FUNCTION public.travel_nearby_locations(p_latitude double precision, p_longitude double precision, p_radius_m double precision, p_category text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS TABLE(id uuid, user_id uuid, title text, description text, coordinates jsonb, created_at timestamp with time zone, image_url text, category text, status text, visibility text, moderation text, updated_at timestamp with time zone, author_name text, author_avatar_url text, distance_m double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select l.id, l.owner_id, l.name, l.description,
         public.st_asgeojson(l.position::public.geometry)::jsonb,
         l.created_at, l.image_url, l.category, l.status::text,
         l.visibility::text, l.moderation, l.updated_at,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), '??????????'),
         p.avatar_url,
         public.st_distance(
           l.position,
           public.st_setsrid(public.st_makepoint(p_longitude, p_latitude), 4326)::public.geography
         ) as distance_m
    from public.locations l
    left join public.profiles p on p.id = l.owner_id
   where l.status = 'approved'::public.location_status
     and l.visibility = 'public'::public.location_visibility
     and public.st_dwithin(
       l.position,
       public.st_setsrid(public.st_makepoint(p_longitude, p_latitude), 4326)::public.geography,
       least(greatest(p_radius_m, 1), 200000)
     )
     and (p_category is null or l.category = p_category)
   order by distance_m asc, l.id desc
   limit least(greatest(coalesce(p_limit, 40), 1), 50)
$function$
;

CREATE OR REPLACE FUNCTION public.update_own_location(p_location_id uuid, p_title text, p_description text, p_category text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE TRIGGER comments_actor_compat BEFORE INSERT OR UPDATE ON comments FOR EACH ROW EXECUTE FUNCTION set_comment_actor_compat();

CREATE TRIGGER comments_notify_location_owner AFTER INSERT ON comments FOR EACH ROW EXECUTE FUNCTION notify_location_owner_about_comment();

CREATE TRIGGER follows_notify_user AFTER INSERT ON follows FOR EACH ROW EXECUTE FUNCTION notify_user_about_follow();

CREATE TRIGGER follows_set_actor_compat BEFORE INSERT ON follows FOR EACH ROW EXECUTE FUNCTION set_follow_actor_compat();

CREATE TRIGGER location_photos_actor_compat BEFORE INSERT OR UPDATE ON location_photos FOR EACH ROW EXECUTE FUNCTION set_photo_actor_compat();

CREATE TRIGGER locations_protect_system_fields BEFORE INSERT OR UPDATE ON locations FOR EACH ROW EXECUTE FUNCTION protect_location_system_fields();

CREATE TRIGGER profiles_server_fields_before_write BEFORE INSERT OR UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_profile_server_fields();

CREATE TRIGGER zz_profiles_level_invite_reward BEFORE UPDATE OF xp ON profiles FOR EACH ROW EXECUTE FUNCTION award_invite_for_level_unlock();

CREATE TRIGGER user_settings_before_update BEFORE UPDATE ON user_settings FOR EACH ROW EXECUTE FUNCTION set_user_settings_updated_at();

alter table public.achievement_definitions enable row level security;

alter table public.categories enable row level security;

alter table public.check_ins enable row level security;

alter table public.comments enable row level security;

alter table public.follows enable row level security;

alter table public.friendships enable row level security;

alter table public.invite_codes enable row level security;

alter table public.invite_redemptions enable row level security;

alter table public.invites enable row level security;

alter table public.location_categories enable row level security;

alter table public.location_photos enable row level security;

alter table public.location_tags enable row level security;

alter table public.locations enable row level security;

alter table public.messages enable row level security;

alter table public.notifications enable row level security;

alter table public.profiles enable row level security;

alter table public.reviews enable row level security;

alter table public.routes enable row level security;

alter table public.tags enable row level security;

alter table public.user_achievements enable row level security;

alter table public.user_settings enable row level security;

create policy achievement_definitions_read on public.achievement_definitions as PERMISSIVE for SELECT to authenticated using (true);

create policy categories_read on public.categories as PERMISSIVE for SELECT to authenticated using (is_active);

create policy check_ins_read on public.check_ins as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

create policy comments_delete on public.comments as PERMISSIVE for DELETE to authenticated using ((author_id = auth.uid()));

create policy comments_insert on public.comments as PERMISSIVE for INSERT to authenticated with check (((author_id = auth.uid()) AND (status = 'visible'::social_content_status) AND (EXISTS ( SELECT 1
   FROM locations l
  WHERE ((l.id = comments.location_id) AND ((l.owner_id = auth.uid()) OR ((l.status = 'approved'::location_status) AND (l.visibility = ANY (ARRAY['public'::location_visibility, 'unlisted'::location_visibility])))))))));

create policy comments_read on public.comments as PERMISSIVE for SELECT to authenticated using (((author_id = auth.uid()) OR ((status = 'visible'::social_content_status) AND (EXISTS ( SELECT 1
   FROM locations l
  WHERE ((l.id = comments.location_id) AND ((l.owner_id = auth.uid()) OR ((l.status = 'approved'::location_status) AND (l.visibility = ANY (ARRAY['public'::location_visibility, 'unlisted'::location_visibility]))))))))));

create policy comments_update on public.comments as PERMISSIVE for UPDATE to authenticated using ((author_id = auth.uid())) with check ((author_id = auth.uid()));

create policy follows_delete on public.follows as PERMISSIVE for DELETE to authenticated using ((follower_id = auth.uid()));

create policy follows_insert on public.follows as PERMISSIVE for INSERT to authenticated with check ((follower_id = auth.uid()));

create policy follows_read on public.follows as PERMISSIVE for SELECT to authenticated using (true);

create policy "Users can delete their friendships" on public.friendships as PERMISSIVE for DELETE to public using (((auth.uid() = user_id_1) OR (auth.uid() = user_id_2)));

create policy "Users can insert their friendships" on public.friendships as PERMISSIVE for INSERT to public with check (((auth.uid() = user_id_1) OR (auth.uid() = user_id_2)));

create policy "Users can update their friendships" on public.friendships as PERMISSIVE for UPDATE to public using (((auth.uid() = user_id_1) OR (auth.uid() = user_id_2)));

create policy "Users can view their friendships" on public.friendships as PERMISSIVE for SELECT to public using (((auth.uid() = user_id_1) OR (auth.uid() = user_id_2)));

create policy location_categories_owner_delete on public.location_categories as PERMISSIVE for DELETE to authenticated using ((EXISTS ( SELECT 1
   FROM locations l
  WHERE ((l.id = location_categories.location_id) AND (l.owner_id = auth.uid())))));

create policy location_categories_owner_insert on public.location_categories as PERMISSIVE for INSERT to authenticated with check ((EXISTS ( SELECT 1
   FROM locations l
  WHERE ((l.id = location_categories.location_id) AND (l.owner_id = auth.uid())))));

create policy location_categories_read on public.location_categories as PERMISSIVE for SELECT to authenticated using (true);

create policy location_photos_owner_delete on public.location_photos as PERMISSIVE for DELETE to authenticated using ((uploader_id = auth.uid()));

create policy location_photos_owner_insert on public.location_photos as PERMISSIVE for INSERT to authenticated with check (((uploader_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM locations l
  WHERE ((l.id = location_photos.location_id) AND (l.owner_id = auth.uid()))))));

create policy location_photos_owner_update on public.location_photos as PERMISSIVE for UPDATE to authenticated using ((uploader_id = auth.uid())) with check ((uploader_id = auth.uid()));

create policy location_photos_read on public.location_photos as PERMISSIVE for SELECT to authenticated using (((uploader_id = auth.uid()) OR (status = 'visible'::social_content_status)));

create policy location_tags_read on public.location_tags as PERMISSIVE for SELECT to authenticated using (true);

create policy locations_delete on public.locations as PERMISSIVE for DELETE to authenticated using (((owner_id = auth.uid()) AND (status = ANY (ARRAY['draft'::location_status, 'rejected'::location_status]))));

create policy locations_insert on public.locations as PERMISSIVE for INSERT to authenticated with check (((owner_id = auth.uid()) AND (status = 'draft'::location_status)));

create policy locations_read on public.locations as PERMISSIVE for SELECT to authenticated using (((owner_id = auth.uid()) OR ((status = 'approved'::location_status) AND (visibility = ANY (ARRAY['public'::location_visibility, 'unlisted'::location_visibility])))));

create policy locations_update on public.locations as PERMISSIVE for UPDATE to authenticated using (((owner_id = auth.uid()) AND (status = ANY (ARRAY['draft'::location_status, 'rejected'::location_status])))) with check (((owner_id = auth.uid()) AND (status = ANY (ARRAY['draft'::location_status, 'rejected'::location_status]))));

create policy messages_friend_insert on public.messages as PERMISSIVE for INSERT to authenticated with check (((sender_id = (auth.uid())::text) AND (receiver_id <> (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM friendships f
  WHERE ((f.status = 'accepted'::text) AND (((f.user_id_1 = auth.uid()) AND ((f.user_id_2)::text = messages.receiver_id)) OR ((f.user_id_2 = auth.uid()) AND ((f.user_id_1)::text = messages.receiver_id))))))));

create policy messages_friend_read on public.messages as PERMISSIVE for SELECT to authenticated using ((((sender_id = (auth.uid())::text) OR (receiver_id = (auth.uid())::text)) AND (EXISTS ( SELECT 1
   FROM friendships f
  WHERE ((f.status = 'accepted'::text) AND ((((f.user_id_1)::text = messages.sender_id) AND ((f.user_id_2)::text = messages.receiver_id)) OR (((f.user_id_2)::text = messages.sender_id) AND ((f.user_id_1)::text = messages.receiver_id))))))));

create policy notifications_read on public.notifications as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

create policy notifications_update on public.notifications as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

create policy profiles_read on public.profiles as PERMISSIVE for SELECT to authenticated using (true);

create policy profiles_update_own on public.profiles as PERMISSIVE for UPDATE to authenticated using ((id = auth.uid())) with check ((id = auth.uid()));

create policy profiles_update_self on public.profiles as PERMISSIVE for UPDATE to authenticated using ((id = auth.uid())) with check ((id = auth.uid()));

create policy "Authenticated users can insert reviews." on public.reviews as PERMISSIVE for INSERT to public with check ((auth.uid() = user_id));

create policy "Reviews are viewable by everyone." on public.reviews as PERMISSIVE for SELECT to public using (true);

create policy "Users can delete their own reviews." on public.reviews as PERMISSIVE for DELETE to public using ((auth.uid() = user_id));

create policy tags_read on public.tags as PERMISSIVE for SELECT to authenticated using (true);

create policy achievements_read on public.user_achievements as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

create policy user_achievements_read_own on public.user_achievements as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

create policy user_settings_self on public.user_settings as PERMISSIVE for ALL to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

create policy avatars_owner_delete on storage.objects as PERMISSIVE for DELETE to authenticated using (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy avatars_owner_insert on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy avatars_owner_update on storage.objects as PERMISSIVE for UPDATE to authenticated using (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))) with check (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy avatars_public_read on storage.objects as PERMISSIVE for SELECT to public using ((bucket_id = 'avatars'::text));

create policy location_images_authenticated_upload on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'location_images'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy location_images_owner_delete on storage.objects as PERMISSIVE for DELETE to authenticated using (((bucket_id = 'location_images'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy location_images_public_read on storage.objects as PERMISSIVE for SELECT to public using ((bucket_id = 'location_images'::text));

revoke all on table public.achievement_definitions from anon, authenticated;

revoke all on table public.categories from anon, authenticated;

revoke all on table public.check_ins from anon, authenticated;

revoke all on table public.comments from anon, authenticated;

revoke all on table public.follows from anon, authenticated;

revoke all on table public.friendships from anon, authenticated;

revoke all on table public.invite_codes from anon, authenticated;

revoke all on table public.invite_redemptions from anon, authenticated;

revoke all on table public.invites from anon, authenticated;

revoke all on table public.location_categories from anon, authenticated;

revoke all on table public.location_photos from anon, authenticated;

revoke all on table public.location_tags from anon, authenticated;

revoke all on table public.locations from anon, authenticated;

revoke all on table public.messages from anon, authenticated;

revoke all on table public.notifications from anon, authenticated;

revoke all on table public.profiles from anon, authenticated;

revoke all on table public.reviews from anon, authenticated;

revoke all on table public.routes from anon, authenticated;

revoke all on table public.tags from anon, authenticated;

revoke all on table public.user_achievements from anon, authenticated;

revoke all on table public.user_settings from anon, authenticated;

grant delete on table public.achievement_definitions to anon;

grant insert on table public.achievement_definitions to anon;

grant references on table public.achievement_definitions to anon;

grant select on table public.achievement_definitions to anon;

grant trigger on table public.achievement_definitions to anon;

grant truncate on table public.achievement_definitions to anon;

grant update on table public.achievement_definitions to anon;

grant delete on table public.achievement_definitions to authenticated;

grant insert on table public.achievement_definitions to authenticated;

grant references on table public.achievement_definitions to authenticated;

grant select on table public.achievement_definitions to authenticated;

grant trigger on table public.achievement_definitions to authenticated;

grant truncate on table public.achievement_definitions to authenticated;

grant update on table public.achievement_definitions to authenticated;

grant select on table public.categories to authenticated;

grant select on table public.check_ins to authenticated;

grant delete on table public.comments to authenticated;

grant select on table public.comments to authenticated;

grant delete on table public.follows to authenticated;

grant select on table public.follows to authenticated;

grant delete on table public.friendships to anon;

grant insert on table public.friendships to anon;

grant references on table public.friendships to anon;

grant select on table public.friendships to anon;

grant trigger on table public.friendships to anon;

grant truncate on table public.friendships to anon;

grant update on table public.friendships to anon;

grant delete on table public.friendships to authenticated;

grant insert on table public.friendships to authenticated;

grant references on table public.friendships to authenticated;

grant select on table public.friendships to authenticated;

grant trigger on table public.friendships to authenticated;

grant truncate on table public.friendships to authenticated;

grant update on table public.friendships to authenticated;

grant delete on table public.location_categories to authenticated;

grant select on table public.location_categories to authenticated;

grant delete on table public.location_photos to authenticated;

grant select on table public.location_photos to authenticated;

grant select on table public.location_tags to authenticated;

grant delete on table public.locations to authenticated;

grant select on table public.locations to authenticated;

grant insert on table public.messages to authenticated;

grant references on table public.messages to authenticated;

grant select on table public.messages to authenticated;

grant trigger on table public.messages to authenticated;

grant truncate on table public.messages to authenticated;

grant select on table public.notifications to authenticated;

grant select on table public.profiles to authenticated;

grant delete on table public.reviews to anon;

grant insert on table public.reviews to anon;

grant references on table public.reviews to anon;

grant select on table public.reviews to anon;

grant trigger on table public.reviews to anon;

grant truncate on table public.reviews to anon;

grant update on table public.reviews to anon;

grant delete on table public.reviews to authenticated;

grant insert on table public.reviews to authenticated;

grant references on table public.reviews to authenticated;

grant select on table public.reviews to authenticated;

grant trigger on table public.reviews to authenticated;

grant truncate on table public.reviews to authenticated;

grant update on table public.reviews to authenticated;

grant select on table public.tags to authenticated;

grant select on table public.user_achievements to authenticated;

grant delete on table public.user_settings to authenticated;

grant insert on table public.user_settings to authenticated;

grant select on table public.user_settings to authenticated;

grant update on table public.user_settings to authenticated;

grant insert (body) on table public.comments to authenticated;

grant update (body) on table public.comments to authenticated;

grant insert (location_id) on table public.comments to authenticated;

grant insert (parent_id) on table public.comments to authenticated;

grant insert (rating) on table public.comments to authenticated;

grant update (rating) on table public.comments to authenticated;

grant insert (following_id) on table public.follows to authenticated;

grant insert (category_id) on table public.location_categories to authenticated;

grant insert (location_id) on table public.location_categories to authenticated;

grant insert (caption) on table public.location_photos to authenticated;

grant update (caption) on table public.location_photos to authenticated;

grant insert (location_id) on table public.location_photos to authenticated;

grant insert (sort_order) on table public.location_photos to authenticated;

grant update (sort_order) on table public.location_photos to authenticated;

grant insert (storage_path) on table public.location_photos to authenticated;

grant insert (category) on table public.locations to authenticated;

grant update (category) on table public.locations to authenticated;

grant insert (description) on table public.locations to authenticated;

grant update (description) on table public.locations to authenticated;

grant insert (has_parking) on table public.locations to authenticated;

grant update (has_parking) on table public.locations to authenticated;

grant insert (image_url) on table public.locations to authenticated;

grant update (image_url) on table public.locations to authenticated;

grant insert (name) on table public.locations to authenticated;

grant update (name) on table public.locations to authenticated;

grant insert ("position") on table public.locations to authenticated;

grant update ("position") on table public.locations to authenticated;

grant insert (road_difficulty) on table public.locations to authenticated;

grant update (road_difficulty) on table public.locations to authenticated;

grant insert (safety) on table public.locations to authenticated;

grant update (safety) on table public.locations to authenticated;

grant insert (visibility) on table public.locations to authenticated;

grant update (visibility) on table public.locations to authenticated;

grant update (is_read) on table public.notifications to authenticated;

grant update (avatar_url) on table public.profiles to authenticated;

grant update (display_name) on table public.profiles to authenticated;

grant update (name) on table public.profiles to authenticated;

grant update (username) on table public.profiles to authenticated;

revoke all on function public.achievement_metric_value(p_uid uuid, p_metric text) from public, anon, authenticated, service_role;

revoke all on function public.award_invite_for_level_unlock() from public, anon, authenticated, service_role;

revoke all on function public.calculate_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) from public, anon, authenticated, service_role;

revoke all on function public.check_and_unlock_achievements() from public, anon, authenticated, service_role;

revoke all on function public.create_check_in(target_location_id uuid, user_lat double precision, user_lng double precision, gps_accuracy_m double precision) from public, anon, authenticated, service_role;

revoke all on function public.create_invite() from public, anon, authenticated, service_role;

revoke all on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text) from public, anon, authenticated, service_role;

revoke all on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text, p_request_id uuid) from public, anon, authenticated, service_role;

revoke all on function public.get_achievement_progress() from public, anon, authenticated, service_role;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated, service_role;

revoke all on function public.handle_new_auth_user_compat() from public, anon, authenticated, service_role;

revoke all on function public.handle_new_user() from public, anon, authenticated, service_role;

revoke all on function public.notify_location_owner_about_comment() from public, anon, authenticated, service_role;

revoke all on function public.notify_user_about_follow() from public, anon, authenticated, service_role;

revoke all on function public.profile_level_for_xp(points integer) from public, anon, authenticated, service_role;

revoke all on function public.protect_location_system_fields() from public, anon, authenticated, service_role;

revoke all on function public.redeem_invite(p_code text) from public, anon, authenticated, service_role;

revoke all on function public.set_comment_actor_compat() from public, anon, authenticated, service_role;

revoke all on function public.set_follow_actor_compat() from public, anon, authenticated, service_role;

revoke all on function public.set_photo_actor_compat() from public, anon, authenticated, service_role;

revoke all on function public.set_profile_server_fields() from public, anon, authenticated, service_role;

revoke all on function public.set_user_settings_updated_at() from public, anon, authenticated, service_role;

revoke all on function public.travel_discover_locations(p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_category text, p_search text, p_limit integer) from public, anon, authenticated, service_role;

revoke all on function public.travel_level_tier(points integer) from public, anon, authenticated, service_role;

revoke all on function public.travel_locations_in_bounds(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_category text, p_search text, p_limit integer) from public, anon, authenticated, service_role;

revoke all on function public.travel_nearby_locations(p_latitude double precision, p_longitude double precision, p_radius_m double precision, p_category text, p_limit integer) from public, anon, authenticated, service_role;

revoke all on function public.update_own_location(p_location_id uuid, p_title text, p_description text, p_category text) from public, anon, authenticated, service_role;

grant execute on function public.achievement_metric_value(p_uid uuid, p_metric text) to anon;

grant execute on function public.achievement_metric_value(p_uid uuid, p_metric text) to authenticated;

grant execute on function public.achievement_metric_value(p_uid uuid, p_metric text) to service_role;

grant execute on function public.award_invite_for_level_unlock() to anon;

grant execute on function public.award_invite_for_level_unlock() to authenticated;

grant execute on function public.award_invite_for_level_unlock() to service_role;

grant execute on function public.calculate_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) to public;

grant execute on function public.calculate_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) to anon;

grant execute on function public.calculate_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) to authenticated;

grant execute on function public.calculate_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) to service_role;

grant execute on function public.check_and_unlock_achievements() to anon;

grant execute on function public.check_and_unlock_achievements() to authenticated;

grant execute on function public.check_and_unlock_achievements() to service_role;

grant execute on function public.create_check_in(target_location_id uuid, user_lat double precision, user_lng double precision, gps_accuracy_m double precision) to anon;

grant execute on function public.create_check_in(target_location_id uuid, user_lat double precision, user_lng double precision, gps_accuracy_m double precision) to authenticated;

grant execute on function public.create_check_in(target_location_id uuid, user_lat double precision, user_lng double precision, gps_accuracy_m double precision) to service_role;

grant execute on function public.create_invite() to authenticated;

grant execute on function public.create_invite() to service_role;

grant execute on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text) to anon;

grant execute on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text) to authenticated;

grant execute on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text) to service_role;

grant execute on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text, p_request_id uuid) to anon;

grant execute on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text, p_request_id uuid) to authenticated;

grant execute on function public.create_location_with_xp(location_title text, location_description text, location_latitude double precision, location_longitude double precision, p_image_url text, p_category text, p_request_id uuid) to service_role;

grant execute on function public.get_achievement_progress() to anon;

grant execute on function public.get_achievement_progress() to authenticated;

grant execute on function public.get_achievement_progress() to service_role;

grant execute on function public.handle_new_auth_user() to anon;

grant execute on function public.handle_new_auth_user() to authenticated;

grant execute on function public.handle_new_auth_user() to service_role;

grant execute on function public.handle_new_auth_user_compat() to public;

grant execute on function public.handle_new_auth_user_compat() to anon;

grant execute on function public.handle_new_auth_user_compat() to authenticated;

grant execute on function public.handle_new_auth_user_compat() to service_role;

grant execute on function public.handle_new_user() to public;

grant execute on function public.handle_new_user() to anon;

grant execute on function public.handle_new_user() to authenticated;

grant execute on function public.handle_new_user() to service_role;

grant execute on function public.notify_location_owner_about_comment() to public;

grant execute on function public.notify_location_owner_about_comment() to anon;

grant execute on function public.notify_location_owner_about_comment() to authenticated;

grant execute on function public.notify_location_owner_about_comment() to service_role;

grant execute on function public.notify_user_about_follow() to public;

grant execute on function public.notify_user_about_follow() to anon;

grant execute on function public.notify_user_about_follow() to authenticated;

grant execute on function public.notify_user_about_follow() to service_role;

grant execute on function public.profile_level_for_xp(points integer) to anon;

grant execute on function public.profile_level_for_xp(points integer) to authenticated;

grant execute on function public.profile_level_for_xp(points integer) to service_role;

grant execute on function public.protect_location_system_fields() to anon;

grant execute on function public.protect_location_system_fields() to authenticated;

grant execute on function public.protect_location_system_fields() to service_role;

grant execute on function public.redeem_invite(p_code text) to authenticated;

grant execute on function public.redeem_invite(p_code text) to service_role;

grant execute on function public.set_comment_actor_compat() to public;

grant execute on function public.set_comment_actor_compat() to anon;

grant execute on function public.set_comment_actor_compat() to authenticated;

grant execute on function public.set_comment_actor_compat() to service_role;

grant execute on function public.set_follow_actor_compat() to public;

grant execute on function public.set_follow_actor_compat() to anon;

grant execute on function public.set_follow_actor_compat() to authenticated;

grant execute on function public.set_follow_actor_compat() to service_role;

grant execute on function public.set_photo_actor_compat() to public;

grant execute on function public.set_photo_actor_compat() to anon;

grant execute on function public.set_photo_actor_compat() to authenticated;

grant execute on function public.set_photo_actor_compat() to service_role;

grant execute on function public.set_profile_server_fields() to anon;

grant execute on function public.set_profile_server_fields() to authenticated;

grant execute on function public.set_profile_server_fields() to service_role;

grant execute on function public.set_user_settings_updated_at() to anon;

grant execute on function public.set_user_settings_updated_at() to authenticated;

grant execute on function public.set_user_settings_updated_at() to service_role;

grant execute on function public.travel_discover_locations(p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_category text, p_search text, p_limit integer) to public;

grant execute on function public.travel_discover_locations(p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_category text, p_search text, p_limit integer) to anon;

grant execute on function public.travel_discover_locations(p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_category text, p_search text, p_limit integer) to authenticated;

grant execute on function public.travel_discover_locations(p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_category text, p_search text, p_limit integer) to service_role;

grant execute on function public.travel_level_tier(points integer) to anon;

grant execute on function public.travel_level_tier(points integer) to authenticated;

grant execute on function public.travel_level_tier(points integer) to service_role;

grant execute on function public.travel_locations_in_bounds(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_category text, p_search text, p_limit integer) to public;

grant execute on function public.travel_locations_in_bounds(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_category text, p_search text, p_limit integer) to anon;

grant execute on function public.travel_locations_in_bounds(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_category text, p_search text, p_limit integer) to authenticated;

grant execute on function public.travel_locations_in_bounds(p_min_lng double precision, p_min_lat double precision, p_max_lng double precision, p_max_lat double precision, p_category text, p_search text, p_limit integer) to service_role;

grant execute on function public.travel_nearby_locations(p_latitude double precision, p_longitude double precision, p_radius_m double precision, p_category text, p_limit integer) to public;

grant execute on function public.travel_nearby_locations(p_latitude double precision, p_longitude double precision, p_radius_m double precision, p_category text, p_limit integer) to anon;

grant execute on function public.travel_nearby_locations(p_latitude double precision, p_longitude double precision, p_radius_m double precision, p_category text, p_limit integer) to authenticated;

grant execute on function public.travel_nearby_locations(p_latitude double precision, p_longitude double precision, p_radius_m double precision, p_category text, p_limit integer) to service_role;

grant execute on function public.update_own_location(p_location_id uuid, p_title text, p_description text, p_category text) to anon;

grant execute on function public.update_own_location(p_location_id uuid, p_title text, p_description text, p_category text) to authenticated;

grant execute on function public.update_own_location(p_location_id uuid, p_title text, p_description text, p_category text) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('avatars','avatars',true,10485760,array['image/jpeg','image/png','image/webp','image/heic']), ('location_images','location_images',true,10485760,array['image/jpeg','image/png','image/webp','image/heic']) on conflict(id) do update set name=excluded.name,public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Project-owned auth trigger lives on a Supabase-managed table.
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user_compat();

-- Factual legacy storage policies retained without recreating the absent
-- places_photos bucket. SECURITY HARDENING REQUIRED AFTER BASELINE.
create policy "All Access 31i9xw_0" on storage.objects as PERMISSIVE for SELECT to authenticated using ((bucket_id = 'places_photos'::text));
create policy "All Access 31i9xw_1" on storage.objects as PERMISSIVE for UPDATE to authenticated using ((bucket_id = 'places_photos'::text));
create policy "All Access 31i9xw_2" on storage.objects as PERMISSIVE for DELETE to authenticated using ((bucket_id = 'places_photos'::text));
create policy "All Access 31i9xw_3" on storage.objects as PERMISSIVE for INSERT to authenticated with check ((bucket_id = 'places_photos'::text));
