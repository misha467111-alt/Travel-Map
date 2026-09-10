-- Additive, read-only query surface for bounded Travel client reads.
-- No tables, policies, XP, invite, or auth behavior are changed.

create or replace function public.travel_locations_in_bounds(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_category text default null,
  p_search text default null,
  p_limit integer default 300
)
returns table (
  id uuid, user_id uuid, title text, description text, coordinates jsonb,
  created_at timestamptz, image_url text, category text, status text,
  visibility text, moderation text, updated_at timestamptz,
  author_name text, author_avatar_url text
)
language sql stable security invoker set search_path = '' as $$
  select l.id, l.owner_id, l.name, l.description,
         public.st_asgeojson(l.position::public.geometry)::jsonb,
         l.created_at, l.image_url, l.category, l.status::text,
         l.visibility::text, l.moderation, l.updated_at,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), 'Мандрівник'),
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
$$;

create or replace function public.travel_discover_locations(
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_category text default null,
  p_search text default null,
  p_limit integer default 30
)
returns table (
  id uuid, user_id uuid, title text, description text, coordinates jsonb,
  created_at timestamptz, image_url text, category text, status text,
  visibility text, moderation text, updated_at timestamptz,
  author_name text, author_avatar_url text
)
language sql stable security invoker set search_path = '' as $$
  select l.id, l.owner_id, l.name, l.description,
         public.st_asgeojson(l.position::public.geometry)::jsonb,
         l.created_at, l.image_url, l.category, l.status::text,
         l.visibility::text, l.moderation, l.updated_at,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), 'Мандрівник'),
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
$$;

create or replace function public.travel_nearby_locations(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_m double precision,
  p_category text default null,
  p_limit integer default 40
)
returns table (
  id uuid, user_id uuid, title text, description text, coordinates jsonb,
  created_at timestamptz, image_url text, category text, status text,
  visibility text, moderation text, updated_at timestamptz,
  author_name text, author_avatar_url text, distance_m double precision
)
language sql stable security invoker set search_path = '' as $$
  select l.id, l.owner_id, l.name, l.description,
         public.st_asgeojson(l.position::public.geometry)::jsonb,
         l.created_at, l.image_url, l.category, l.status::text,
         l.visibility::text, l.moderation, l.updated_at,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(p.username), ''), 'Мандрівник'),
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
$$;

grant execute on function public.travel_locations_in_bounds(double precision,double precision,double precision,double precision,text,text,integer) to authenticated;
grant execute on function public.travel_discover_locations(timestamptz,uuid,text,text,integer) to authenticated;
grant execute on function public.travel_nearby_locations(double precision,double precision,double precision,text,integer) to authenticated;

create index if not exists messages_sender_recipient_created_idx
  on public.messages(sender_id, receiver_id, "timestamp" desc);
create index if not exists follows_follower_created_idx
  on public.follows(follower_id, created_at desc);
