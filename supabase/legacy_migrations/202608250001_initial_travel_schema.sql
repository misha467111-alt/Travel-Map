begin;

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.road_difficulty as enum ('easy','moderate','hard','offroad');
create type public.safety_level as enum ('unknown','low','medium','high');
create type public.secrecy_level as enum ('public','hidden','secret');
create type public.route_visibility as enum ('public','private');
create type public.moderation_status as enum ('pending','approved','rejected');
create type public.place_condition as enum ('crowded','closed','bad_road','beautiful_now','trash');

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 30),
  display_name text not null default '', avatar_url text,
  xp integer not null default 0 check (xp >= 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.invites (
  code text primary key, created_by uuid references public.profiles(id),
  max_uses integer not null default 1 check(max_uses > 0), uses integer not null default 0,
  expires_at timestamptz, created_at timestamptz not null default now()
);
create table public.invite_redemptions (
  code text references public.invites(code), user_id uuid unique references public.profiles(id) on delete cascade,
  redeemed_at timestamptz not null default now(), primary key(code,user_id)
);
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(), slug text unique not null, name text not null, icon text not null default ''
);
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id),
  name text not null check(char_length(name) between 3 and 120), description text not null default '',
  position extensions.geography(point,4326) not null,
  road_difficulty public.road_difficulty not null default 'easy', has_parking boolean not null default false,
  safety public.safety_level not null default 'unknown', secrecy public.secrecy_level not null default 'public',
  minimum_xp integer not null default 0, moderation public.moderation_status not null default 'pending',
  rating numeric(3,2) not null default 0, ratings_count integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index locations_position_gix on public.locations using gist(position);
create index locations_name_trgm on public.locations using gin(name extensions.gin_trgm_ops);
create index locations_feed_idx on public.locations(moderation,secrecy,created_at desc);
create table if not exists public.location_categories (
  location_id uuid references public.locations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete cascade, primary key(location_id,category_id)
);
create table public.location_media (
  id uuid primary key default gen_random_uuid(), location_id uuid not null references public.locations(id) on delete cascade,
  owner_id uuid not null references public.profiles(id), storage_path text not null unique,
  media_type text not null check(media_type in ('image','video')),
  moderation public.moderation_status not null default 'pending', created_at timestamptz not null default now()
);
create table public.reviews (
  id uuid primary key default gen_random_uuid(), location_id uuid not null references public.locations(id) on delete cascade,
  author_id uuid not null references public.profiles(id), rating smallint not null check(rating between 1 and 5),
  body text not null check(char_length(body) between 1 and 2000), helpful_count integer not null default 0,
  created_at timestamptz not null default now(), unique(location_id,author_id)
);
create table public.check_ins (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  position extensions.geography(point,4326) not null, accuracy_m numeric not null,
  created_at timestamptz not null default now()
);
create index check_ins_user_time_idx on public.check_ins(user_id,created_at desc);
create index check_ins_position_gix on public.check_ins using gist(position);
create unique index one_checkin_per_place_per_day on public.check_ins(user_id,location_id,((created_at at time zone 'utc')::date));
create table public.xp_events (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null, source_id uuid not null, points integer not null check(points between 1 and 500),
  created_at timestamptz not null default now(), unique(user_id,source_type,source_id)
);
create table public.badges (
  id uuid primary key default gen_random_uuid(), slug text unique not null, name text not null, description text not null,
  rule jsonb not null default '{}'
);
create table public.user_badges (
  user_id uuid references public.profiles(id) on delete cascade, badge_id uuid references public.badges(id) on delete cascade,
  earned_at timestamptz not null default now(), primary key(user_id,badge_id)
);
create table public.place_conditions (
  id uuid primary key default gen_random_uuid(), location_id uuid not null references public.locations(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id), condition public.place_condition not null,
  created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '24 hours'
);
create table public.routes (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id), title text not null,
  description text not null default '', visibility public.route_visibility not null default 'private',
  is_offline_ready boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.route_members (
  route_id uuid references public.routes(id) on delete cascade, user_id uuid references public.profiles(id) on delete cascade,
  can_edit boolean not null default false, primary key(route_id,user_id)
);
create table public.route_stops (
  route_id uuid references public.routes(id) on delete cascade, location_id uuid references public.locations(id),
  position integer not null check(position >= 0), notes text not null default '', primary key(route_id,position)
);
create table public.collections (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id), title text not null,
  is_public boolean not null default false, created_at timestamptz not null default now()
);
create table public.collection_locations (
  collection_id uuid references public.collections(id) on delete cascade, location_id uuid references public.locations(id) on delete cascade,
  added_at timestamptz not null default now(), primary key(collection_id,location_id)
);
create table public.posts (
  id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles(id),
  location_id uuid not null references public.locations(id), media_path text not null, caption text not null default '',
  moderation public.moderation_status not null default 'pending', created_at timestamptz not null default now()
);
create index posts_feed_idx on public.posts(moderation,created_at desc);

create or replace view public.location_details with (security_invoker=true) as
select l.*, st_y(l.position::extensions.geometry) latitude, st_x(l.position::extensions.geometry) longitude,
 coalesce(array_agg(distinct lc.category_id::text) filter(where lc.category_id is not null),'{}') category_ids,
 coalesce(array_agg(distinct m.storage_path) filter(where m.moderation='approved'),'{}') photo_urls
from public.locations l left join public.location_categories lc on lc.location_id=l.id
left join public.location_media m on m.location_id=l.id group by l.id;

create or replace function public.locations_in_bounds(min_lng float8,min_lat float8,max_lng float8,max_lat float8,
 category_filter uuid[] default '{}',search_query text default '',result_limit integer default 300)
returns setof public.location_details language sql stable security invoker set search_path='' as $$
 select d.* from public.location_details d where d.position && extensions.st_makeenvelope(min_lng,min_lat,max_lng,max_lat,4326)::extensions.geography
 and (cardinality(category_filter)=0 or d.category_ids::uuid[] && category_filter)
 and (search_query='' or d.name ilike '%'||search_query||'%') order by d.rating desc limit least(result_limit,500)
$$;

create or replace function public.create_check_in(target_location_id uuid,user_lat float8,user_lng float8,gps_accuracy_m float8)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare uid uuid:=auth.uid(); target geography; cid uuid; awarded integer:=20;
begin
 if uid is null then raise exception 'authentication required'; end if;
 if gps_accuracy_m<0 or gps_accuracy_m>100 then raise exception 'GPS accuracy is insufficient'; end if;
 select position into target from locations where id=target_location_id and moderation='approved';
 if target is null then raise exception 'location unavailable'; end if;
 if st_distance(target,st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography)>100 then raise exception 'must be within 100 meters'; end if;
 insert into check_ins(user_id,location_id,position,accuracy_m) values(uid,target_location_id,st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography,gps_accuracy_m) returning id into cid;
 insert into xp_events(user_id,source_type,source_id,points) values(uid,'check_in',cid,awarded);
 update profiles set xp=xp+awarded,updated_at=now() where id=uid;
 return jsonb_build_object('check_in_id',cid,'xp_awarded',awarded);
end $$;
revoke all on function public.create_check_in(uuid,float8,float8,float8) from public;
grant execute on function public.create_check_in(uuid,float8,float8,float8) to authenticated;

create or replace function public.nearby_discovery_candidates(user_lat float8,user_lng float8,radius_m float8,mood_filter uuid[] default '{}')
returns table(id uuid,name text,latitude float8,longitude float8,distance_m float8,rating numeric)
language sql stable security invoker set search_path='public','extensions' as $$
 select l.id,l.name,st_y(l.position::geometry),st_x(l.position::geometry),
   st_distance(l.position,st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography),l.rating
 from locations l where st_dwithin(l.position,st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography,least(radius_m,200000))
 and l.moderation='approved'
 and (cardinality(mood_filter)=0 or exists(select 1 from location_categories lc where lc.location_id=l.id and lc.category_id=any(mood_filter)))
 order by l.rating desc,distance_m asc limit 50
$$;

alter table public.profiles enable row level security; alter table public.locations enable row level security;
alter table public.location_categories enable row level security; alter table public.location_media enable row level security;
alter table public.reviews enable row level security; alter table public.check_ins enable row level security;
alter table public.xp_events enable row level security; alter table public.user_badges enable row level security;
alter table public.place_conditions enable row level security; alter table public.routes enable row level security;
alter table public.route_members enable row level security; alter table public.route_stops enable row level security;
alter table public.collections enable row level security; alter table public.collection_locations enable row level security;
alter table public.posts enable row level security; alter table public.invites enable row level security;
alter table public.invite_redemptions enable row level security;

create policy profiles_read on public.profiles for select to authenticated using(true);
create policy locations_read on public.locations for select to authenticated using(moderation='approved' and (secrecy='public' or owner_id=auth.uid()) and minimum_xp<=coalesce((select xp from profiles where id=auth.uid()),0));
create policy locations_create on public.locations for insert to authenticated with check(owner_id=auth.uid() and moderation='pending');
create policy locations_owner_update on public.locations for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid() and moderation='pending');
create policy location_categories_read on public.location_categories for select to authenticated using(exists(select 1 from locations l where l.id=location_id));
create policy media_read on public.location_media for select to authenticated using(moderation='approved' or owner_id=auth.uid());
create policy media_create on public.location_media for insert to authenticated with check(owner_id=auth.uid() and moderation='pending');
create policy reviews_read on public.reviews for select to authenticated using(true);
create policy reviews_own on public.reviews for all to authenticated using(author_id=auth.uid()) with check(author_id=auth.uid());
create policy checkins_self_read on public.check_ins for select to authenticated using(user_id=auth.uid());
create policy xp_self_read on public.xp_events for select to authenticated using(user_id=auth.uid());
create policy badges_self_read on public.user_badges for select to authenticated using(user_id=auth.uid());
create policy conditions_read on public.place_conditions for select to authenticated using(expires_at>now());
create policy conditions_create on public.place_conditions for insert to authenticated with check(reporter_id=auth.uid());
create policy routes_read on public.routes for select to authenticated using(visibility='public' or owner_id=auth.uid() or exists(select 1 from route_members rm where rm.route_id=id and rm.user_id=auth.uid()));
create policy routes_owner on public.routes for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy collections_read on public.collections for select to authenticated using(is_public or owner_id=auth.uid());
create policy collections_owner on public.collections for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy posts_read on public.posts for select to authenticated using(moderation='approved' or author_id=auth.uid());
create policy posts_create on public.posts for insert to authenticated with check(author_id=auth.uid() and moderation='pending');

insert into public.badges(slug,name,description,rule) values
 ('ten_lakes','10 озер','Відвідайте 10 озер','{"category":"lake","count":10}'),
 ('sunsets_20','20 заходів сонця','Відвідайте 20 місць на заході','{"category":"sunset","count":20}'),
 ('checkins_50','50 чекінів','Зробіть 50 чекінів','{"check_ins":50}'),
 ('night_explorer','Нічний дослідник','Зробіть нічний чекін','{"hour_from":22,"hour_to":5}')
on conflict do nothing;

commit;
