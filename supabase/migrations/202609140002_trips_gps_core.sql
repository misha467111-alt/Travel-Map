-- GPS-1 — SERVER SCHEMA: trips, recorded_routes, route_points,
-- route_waypoints, recorded_route_events, finalize_recorded_route().
--
-- Design-only until reviewed: this migration is NOT applied by this
-- change. It is created and statically reviewed, per explicit
-- instruction, and must not be pushed without separate approval.
--
-- Revised in a final pre-apply correctness/security review pass (still
-- unapplied): bounding_box's column type, finalize_recorded_route's
-- 0/1/2+ point handling, its idempotency, its duplicate-pause-event
-- safety, and protect_recorded_route_system_fields' status-transition
-- guard were all changed from the first draft -- each change is
-- explained inline at its exact location below.
--
-- Confirmed live before writing this migration (not assumed):
--   - No table named trips, recorded_routes, route_points,
--     route_waypoints, or recorded_route_events exists anywhere in the
--     active chain or in production.
--   - No enum named trip_visibility or route_waypoint_type exists. The
--     only existing enums are location_status, location_visibility
--     ('public','unlisted','secret','private' -- no 'friends' tier) and
--     social_content_status; trip_visibility is deliberately a new,
--     separate enum rather than reusing location_visibility, since
--     'friends' has no equivalent there.
--   - The existing public.routes table (text id, jsonb points,
--     liked_by_users, transport_mode) is a manually-authored, shareable
--     itinerary, structurally and conceptually unrelated to the GPS
--     recordings created here. It is not touched, referenced, or
--     repurposed by anything in this migration.
--   - Owner-column FK convention across the schema is
--     `references public.profiles(id) on delete cascade` (confirmed via
--     check_ins.user_id, location_photos.uploader_id), not
--     `auth.users(id)` -- followed here for owner_id everywhere.
--   - PostGIS points are declared `geography(Point,4326)` with no extra
--     trigger-based SRID check on check_ins.position (only
--     locations.position has one, likely belt-and-suspenders since it's
--     also written by an RPC); route_points/route_waypoints rely on the
--     typed column modifier alone, deliberately, to avoid adding
--     BEFORE-INSERT trigger overhead to the highest-volume table in the
--     schema (see the route_points section below).
--   - Field-protection convention is a small dedicated BEFORE
--     INSERT-OR-UPDATE trigger per table (protect_location_system_fields,
--     set_profile_server_fields, set_user_settings_updated_at, etc.),
--     each checking `current_user = 'authenticated'` to distinguish a
--     direct client write from an internal SECURITY DEFINER call -- the
--     exact mechanism reused below for recorded_routes.status and its
--     derived columns, and for finalize_recorded_route.
--   - Column-level INSERT/UPDATE grants (not a blanket table grant) are
--     the established way to make only specific columns client-writable
--     (see profiles.avatar_url/display_name/name/username and every
--     client-writable column of locations) -- followed exactly here.
--   - RLS ownership-through-a-parent-join (not a trusted client-supplied
--     column alone) is already proven in message_user_state_insert and
--     location_photos_owner_insert -- the same join pattern is used below
--     for route_points/route_waypoints/recorded_route_events.
--   - Lesson applied proactively from 202609140001: a bare
--     `create function` grants EXECUTE to PUBLIC by default unless
--     explicitly revoked. Every function created below has an explicit
--     revoke immediately after creation, before any grant.
--
-- Fixed architecture decisions this migration encodes:
--   - trip -> 0..N recorded_routes; recorded_routes.trip_id is nullable.
--   - recorded_routes.id and route_waypoints.id are client-generated
--     UUIDs (no `default gen_random_uuid()`), required for offline-first
--     creation with idempotent later sync.
--   - Raw route_points/route_waypoints/recorded_route_events are
--     owner-only, unconditionally, regardless of the parent
--     recorded_routes.visibility value. Friends/public read of trips or
--     recorded_routes (summary + simplified_geometry only, never raw
--     tables) is deliberately DEFERRED to a later migration: this
--     project has no existing precedent for friendship-gated visibility
--     on arbitrary owned content (the only friendships-based RLS today,
--     messages_friend_read/insert, is shaped for a two-party DM channel,
--     not "any of the owner's friends may read this row"), so GPS-1
--     keeps trips and recorded_routes owner-only even when visibility is
--     'friends' or 'public' -- fails closed, not open. The visibility
--     columns exist now so no later ALTER TABLE is needed once that
--     policy is designed and reviewed on its own.

-- ---------------------------------------------------------------------------
-- 1. Enums
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'trip_visibility' and n.nspname = 'public'
  ) then
    create type public.trip_visibility as enum ('private', 'friends', 'public');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'route_waypoint_type' and n.nspname = 'public'
  ) then
    create type public.route_waypoint_type as enum (
      'mountain_pass', 'campsite', 'overnight', 'rest', 'water',
      'photo_point', 'viewpoint', 'danger', 'parking',
      'interesting_place', 'custom'
    );
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. trips -- higher-level travel story/container. May contain zero or
--    more recorded_routes; never required by one.
-- ---------------------------------------------------------------------------
create table public.trips (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  status text not null default 'active',
  visibility public.trip_visibility not null default 'private',
  started_at timestamptz,
  ended_at timestamptz,
  cover_photo_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trips_title_not_blank_check check (btrim(title) <> ''),
  constraint trips_status_check check (status in ('active', 'completed', 'archived')),
  constraint trips_ended_after_started_check
    check (ended_at is null or started_at is null or ended_at >= started_at)
);

create index trips_owner_created_idx on public.trips (owner_id, created_at desc);

create or replace function public.protect_trip_system_fields()
returns trigger
language plpgsql
set search_path to 'public', 'pg_catalog'
as $$
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' then
      new.owner_id := auth.uid();
    end if;
    new.created_at := coalesce(new.created_at, now());
  elsif current_user = 'authenticated' and (
    new.id is distinct from old.id
    or new.owner_id is distinct from old.owner_id
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'trip identity fields are server-managed' using errcode = '42501';
  end if;

  new.updated_at := now();
  return new;
end
$$;

revoke all on function public.protect_trip_system_fields() from public, anon, authenticated;

drop trigger if exists trips_protect_system_fields on public.trips;
create trigger trips_protect_system_fields
before insert or update on public.trips
for each row execute function public.protect_trip_system_fields();

alter table public.trips enable row level security;

drop policy if exists trips_select on public.trips;
create policy trips_select on public.trips
  for select to authenticated
  using (owner_id = auth.uid());

drop policy if exists trips_insert on public.trips;
create policy trips_insert on public.trips
  for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists trips_update on public.trips;
create policy trips_update on public.trips
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists trips_delete on public.trips;
create policy trips_delete on public.trips
  for delete to authenticated
  using (owner_id = auth.uid());

revoke all on table public.trips from public, anon;
grant select, delete on table public.trips to authenticated;
grant insert (title), update (title) on table public.trips to authenticated;
grant insert (description), update (description) on table public.trips to authenticated;
grant insert (status), update (status) on table public.trips to authenticated;
grant insert (visibility), update (visibility) on table public.trips to authenticated;
grant insert (started_at), update (started_at) on table public.trips to authenticated;
grant insert (ended_at), update (ended_at) on table public.trips to authenticated;
grant insert (cover_photo_ref), update (cover_photo_ref) on table public.trips to authenticated;

-- ---------------------------------------------------------------------------
-- 3. recorded_routes -- one real GPS recording session. id is
--    client-generated (no server default) so an offline-created recording
--    syncs later by idempotent upsert on the same id.
-- ---------------------------------------------------------------------------
create table public.recorded_routes (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  trip_id uuid references public.trips(id) on delete set null,
  title text,
  transport_mode text not null default 'walking',
  status text not null default 'recording',
  visibility public.trip_visibility not null default 'private',
  started_at timestamptz not null,
  ended_at timestamptz,
  -- Derived/summary fields: written only by finalize_recorded_route().
  -- Never directly client-writable -- see the trigger and grants below.
  total_distance_m double precision,
  moving_time_s integer,
  elapsed_time_s integer,
  paused_time_s integer,
  avg_speed_mps double precision,
  max_speed_mps double precision,
  min_altitude_m double precision,
  max_altitude_m double precision,
  elevation_gain_m double precision,
  elevation_loss_m double precision,
  -- Deliberately untyped-subtype geography (any shape, SRID still
  -- pinned to 4326), not geography(Polygon,4326): ST_Envelope degrades
  -- to a POINT for a single-point/all-coincident input and to a
  -- LINESTRING for a perfectly vertical or horizontal input -- a
  -- Polygon-only column would reject those values outright (PostGIS
  -- enforces the declared subtype on typed geography columns) and
  -- finalize_recorded_route would fail on exactly the 1-point case this
  -- review was asked to make safe. See finalize_recorded_route below
  -- for the explicit 0/1/2+ point branching this column type supports.
  bounding_box geography(Geometry, 4326),
  simplified_geometry geography(LineString, 4326),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recorded_routes_transport_mode_check
    check (transport_mode in ('walking', 'running', 'cycling', 'driving', 'other')),
  constraint recorded_routes_status_check
    check (status in ('recording', 'paused', 'completed', 'discarded')),
  constraint recorded_routes_ended_after_started_check
    check (ended_at is null or ended_at >= started_at),
  constraint recorded_routes_distance_nonneg_check
    check (total_distance_m is null or total_distance_m >= 0),
  constraint recorded_routes_moving_time_nonneg_check
    check (moving_time_s is null or moving_time_s >= 0),
  constraint recorded_routes_elapsed_time_nonneg_check
    check (elapsed_time_s is null or elapsed_time_s >= 0),
  constraint recorded_routes_paused_time_nonneg_check
    check (paused_time_s is null or paused_time_s >= 0),
  constraint recorded_routes_avg_speed_nonneg_check
    check (avg_speed_mps is null or avg_speed_mps >= 0),
  constraint recorded_routes_max_speed_nonneg_check
    check (max_speed_mps is null or max_speed_mps >= 0),
  constraint recorded_routes_elevation_gain_nonneg_check
    check (elevation_gain_m is null or elevation_gain_m >= 0),
  constraint recorded_routes_elevation_loss_nonneg_check
    check (elevation_loss_m is null or elevation_loss_m >= 0)
);

create index recorded_routes_owner_created_idx on public.recorded_routes (owner_id, created_at desc);
create index recorded_routes_trip_idx on public.recorded_routes (trip_id) where trip_id is not null;

-- Guards, in order: identity/derived fields are always server-managed;
-- the one remaining risky transition (-> 'completed') is blocked for a
-- direct client write specifically, mirroring exactly how
-- protect_location_system_fields distinguishes `current_user =
-- 'authenticated'` from a SECURITY DEFINER caller (finalize_recorded_route
-- runs as its owner, so this check does not fire for its own UPDATE).
create or replace function public.protect_recorded_route_system_fields()
returns trigger
language plpgsql
set search_path to 'public', 'pg_catalog'
as $$
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' then
      new.owner_id := auth.uid();
      new.status := 'recording';
    end if;
    new.created_at := coalesce(new.created_at, now());
  elsif current_user = 'authenticated' then
    if new.id is distinct from old.id
       or new.owner_id is distinct from old.owner_id
       or new.created_at is distinct from old.created_at
       or new.started_at is distinct from old.started_at
       or new.ended_at is distinct from old.ended_at
       or new.total_distance_m is distinct from old.total_distance_m
       or new.moving_time_s is distinct from old.moving_time_s
       or new.elapsed_time_s is distinct from old.elapsed_time_s
       or new.paused_time_s is distinct from old.paused_time_s
       or new.avg_speed_mps is distinct from old.avg_speed_mps
       or new.max_speed_mps is distinct from old.max_speed_mps
       or new.min_altitude_m is distinct from old.min_altitude_m
       or new.max_altitude_m is distinct from old.max_altitude_m
       or new.elevation_gain_m is distinct from old.elevation_gain_m
       or new.elevation_loss_m is distinct from old.elevation_loss_m
       or new.bounding_box is distinct from old.bounding_box
       or new.simplified_geometry is distinct from old.simplified_geometry
    then
      raise exception 'recorded route system/derived fields are server-managed'
        using errcode = '42501';
    end if;

    -- Explicit allow-list, not a blocklist: 'completed' and 'discarded'
    -- are both terminal states for a direct client write. The only
    -- transitions authenticated may perform directly are the pause/
    -- resume/discard actions a real client issues during a recording;
    -- everything else (completed -> anything, discarded -> anything,
    -- anything -> completed) is rejected, including the previously
    -- unguarded discarded -> recording / discarded -> paused jumps this
    -- review was asked to close off. 'completed' is only ever reachable
    -- through finalize_recorded_route (SECURITY DEFINER, runs as its
    -- owner, so this check does not fire for its own UPDATE).
    if new.status is distinct from old.status
       and not (
         (old.status = 'recording' and new.status in ('paused', 'discarded'))
         or (old.status = 'paused' and new.status in ('recording', 'discarded'))
       )
    then
      raise exception 'invalid recorded route status transition (% -> %)', old.status, new.status
        using errcode = '42501';
    end if;
  end if;

  new.updated_at := now();
  return new;
end
$$;

revoke all on function public.protect_recorded_route_system_fields() from public, anon, authenticated;

drop trigger if exists recorded_routes_protect_system_fields on public.recorded_routes;
create trigger recorded_routes_protect_system_fields
before insert or update on public.recorded_routes
for each row execute function public.protect_recorded_route_system_fields();

alter table public.recorded_routes enable row level security;

drop policy if exists recorded_routes_select on public.recorded_routes;
create policy recorded_routes_select on public.recorded_routes
  for select to authenticated
  using (owner_id = auth.uid());

drop policy if exists recorded_routes_insert on public.recorded_routes;
create policy recorded_routes_insert on public.recorded_routes
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and (
      trip_id is null
      or exists (
        select 1 from public.trips t
        where t.id = recorded_routes.trip_id and t.owner_id = auth.uid()
      )
    )
  );

drop policy if exists recorded_routes_update on public.recorded_routes;
create policy recorded_routes_update on public.recorded_routes
  for update to authenticated
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    and (
      trip_id is null
      or exists (
        select 1 from public.trips t
        where t.id = recorded_routes.trip_id and t.owner_id = auth.uid()
      )
    )
  );

drop policy if exists recorded_routes_delete on public.recorded_routes;
create policy recorded_routes_delete on public.recorded_routes
  for delete to authenticated
  using (owner_id = auth.uid());

revoke all on table public.recorded_routes from public, anon;
grant select, delete on table public.recorded_routes to authenticated;
grant insert (id) on table public.recorded_routes to authenticated;
grant insert (title), update (title) on table public.recorded_routes to authenticated;
grant insert (trip_id), update (trip_id) on table public.recorded_routes to authenticated;
grant insert (transport_mode), update (transport_mode) on table public.recorded_routes to authenticated;
-- status: UPDATE only (recording/paused/discarded transitions), never
-- INSERT -- the trigger above forces 'recording' at creation regardless.
grant update (status) on table public.recorded_routes to authenticated;
grant insert (visibility), update (visibility) on table public.recorded_routes to authenticated;
grant insert (started_at) on table public.recorded_routes to authenticated;
-- ended_at and every derived column: no insert/update grant at all.
-- They are writable only inside finalize_recorded_route(), which runs as
-- the function owner, not as `authenticated`.

-- ---------------------------------------------------------------------------
-- 4. route_points -- raw GPS samples. Highest-volume table in this
--    migration by a wide margin (potentially hundreds of millions of
--    rows over the project's lifetime). Kept deliberately minimal:
--      - PK (recorded_route_id, seq): no per-row UUID. Smaller, naturally
--        clustered by recording, append-friendly for inserts, and
--        partition-friendly (by recorded_route_id or a future
--        recorded_at range) if partitioning is ever introduced later --
--        not done in this migration.
--      - No trigger: there is no server-managed field on this table
--        (recorded_at is the client's own device clock, intentionally
--        not overwritten) and no derived value to protect, so a
--        BEFORE-INSERT trigger would add per-row PL/pgSQL overhead to
--        the hottest table in the schema for zero benefit.
--      - No extra SRID check: geography(Point,4326) enforces SRID 4326
--        at the type level already (the same as check_ins.position,
--        which also has no redundant trigger check).
--      - No secondary index beyond the PK -- see the comment below it.
--      - No UPDATE/DELETE grant: raw samples are immutable and
--        append-only; removal only happens via ON DELETE CASCADE when
--        the parent recorded_routes row is deleted.
-- ---------------------------------------------------------------------------
create table public.route_points (
  recorded_route_id uuid not null references public.recorded_routes(id) on delete cascade,
  seq integer not null,
  position geography(Point, 4326) not null,
  altitude_m double precision,
  horizontal_accuracy_m double precision,
  vertical_accuracy_m double precision,
  speed_mps double precision,
  speed_accuracy_mps double precision,
  heading_deg double precision,
  heading_accuracy_deg double precision,
  recorded_at timestamptz not null,
  provider text,
  created_at timestamptz not null default now(),
  primary key (recorded_route_id, seq),
  constraint route_points_seq_positive_check check (seq > 0),
  constraint route_points_horizontal_accuracy_nonneg_check
    check (horizontal_accuracy_m is null or horizontal_accuracy_m >= 0),
  constraint route_points_vertical_accuracy_nonneg_check
    check (vertical_accuracy_m is null or vertical_accuracy_m >= 0),
  constraint route_points_speed_nonneg_check
    check (speed_mps is null or speed_mps >= 0),
  constraint route_points_speed_accuracy_nonneg_check
    check (speed_accuracy_mps is null or speed_accuracy_mps >= 0),
  constraint route_points_heading_range_check
    check (heading_deg is null or (heading_deg >= 0 and heading_deg < 360)),
  constraint route_points_heading_accuracy_nonneg_check
    check (heading_accuracy_deg is null or heading_accuracy_deg >= 0)
);

-- No secondary index: every real access pattern (read or insert one
-- recording's points) is already served by the PK's leading column.
-- Deliberately not adding one "just in case" on this table.

alter table public.route_points enable row level security;

drop policy if exists route_points_select on public.route_points;
create policy route_points_select on public.route_points
  for select to authenticated
  using (
    exists (
      select 1 from public.recorded_routes r
      where r.id = route_points.recorded_route_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists route_points_insert on public.route_points;
create policy route_points_insert on public.route_points
  for insert to authenticated
  with check (
    exists (
      select 1 from public.recorded_routes r
      where r.id = route_points.recorded_route_id and r.owner_id = auth.uid()
    )
  );

revoke all on table public.route_points from public, anon;
grant select on table public.route_points to authenticated;
grant insert (recorded_route_id) on table public.route_points to authenticated;
grant insert (seq) on table public.route_points to authenticated;
grant insert (position) on table public.route_points to authenticated;
grant insert (altitude_m) on table public.route_points to authenticated;
grant insert (horizontal_accuracy_m) on table public.route_points to authenticated;
grant insert (vertical_accuracy_m) on table public.route_points to authenticated;
grant insert (speed_mps) on table public.route_points to authenticated;
grant insert (speed_accuracy_mps) on table public.route_points to authenticated;
grant insert (heading_deg) on table public.route_points to authenticated;
grant insert (heading_accuracy_deg) on table public.route_points to authenticated;
grant insert (recorded_at) on table public.route_points to authenticated;
grant insert (provider) on table public.route_points to authenticated;

-- ---------------------------------------------------------------------------
-- 5. route_waypoints -- typed points, independent of recording/paused
--    state. Unlike route_points, low volume and occasionally edited
--    (title/note/type) after creation, so it gets the identity-protection
--    trigger + a scoped UPDATE grant.
-- ---------------------------------------------------------------------------
create table public.route_waypoints (
  id uuid primary key,
  recorded_route_id uuid not null references public.recorded_routes(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  waypoint_type public.route_waypoint_type not null,
  title text,
  note text,
  position geography(Point, 4326) not null,
  altitude_m double precision,
  recorded_at timestamptz not null,
  photo_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index route_waypoints_route_recorded_idx on public.route_waypoints (recorded_route_id, recorded_at);

create or replace function public.protect_route_waypoint_system_fields()
returns trigger
language plpgsql
set search_path to 'public', 'pg_catalog'
as $$
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' then
      new.owner_id := auth.uid();
    end if;
    new.created_at := coalesce(new.created_at, now());
  elsif current_user = 'authenticated' and (
    new.id is distinct from old.id
    or new.owner_id is distinct from old.owner_id
    or new.recorded_route_id is distinct from old.recorded_route_id
    or new.position is distinct from old.position
    or new.altitude_m is distinct from old.altitude_m
    or new.recorded_at is distinct from old.recorded_at
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'waypoint telemetry/identity fields are immutable once recorded'
      using errcode = '42501';
  end if;

  new.updated_at := now();
  return new;
end
$$;

revoke all on function public.protect_route_waypoint_system_fields() from public, anon, authenticated;

drop trigger if exists route_waypoints_protect_system_fields on public.route_waypoints;
create trigger route_waypoints_protect_system_fields
before insert or update on public.route_waypoints
for each row execute function public.protect_route_waypoint_system_fields();

alter table public.route_waypoints enable row level security;

drop policy if exists route_waypoints_select on public.route_waypoints;
create policy route_waypoints_select on public.route_waypoints
  for select to authenticated
  using (owner_id = auth.uid());

drop policy if exists route_waypoints_insert on public.route_waypoints;
create policy route_waypoints_insert on public.route_waypoints
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.recorded_routes r
      where r.id = route_waypoints.recorded_route_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists route_waypoints_update on public.route_waypoints;
create policy route_waypoints_update on public.route_waypoints
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists route_waypoints_delete on public.route_waypoints;
create policy route_waypoints_delete on public.route_waypoints
  for delete to authenticated
  using (owner_id = auth.uid());

revoke all on table public.route_waypoints from public, anon;
grant select, delete on table public.route_waypoints to authenticated;
grant insert (id) on table public.route_waypoints to authenticated;
grant insert (recorded_route_id) on table public.route_waypoints to authenticated;
grant insert (waypoint_type), update (waypoint_type) on table public.route_waypoints to authenticated;
grant insert (title), update (title) on table public.route_waypoints to authenticated;
grant insert (note), update (note) on table public.route_waypoints to authenticated;
grant insert (position) on table public.route_waypoints to authenticated;
grant insert (altitude_m) on table public.route_waypoints to authenticated;
grant insert (recorded_at) on table public.route_waypoints to authenticated;
grant insert (photo_ref), update (photo_ref) on table public.route_waypoints to authenticated;

-- ---------------------------------------------------------------------------
-- 6. recorded_route_events -- append-only lifecycle/pause log. Chosen
--    over per-point moving/paused flags (redundant: the recorder simply
--    stops writing route_points while paused, so a per-point flag would
--    always read true) and over a pre-closed pause-segments table (which
--    would need to "close" a row on resume -- unsafe under a crash/kill
--    mid-pause with no resume ever recorded). An unresolved trailing
--    pause is handled by finalize_recorded_route() counting time through
--    to the finish/discard event instead.
-- ---------------------------------------------------------------------------
create table public.recorded_route_events (
  recorded_route_id uuid not null references public.recorded_routes(id) on delete cascade,
  seq integer not null,
  event_type text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (recorded_route_id, seq),
  constraint recorded_route_events_seq_positive_check check (seq > 0),
  constraint recorded_route_events_type_check
    check (event_type in ('start', 'pause', 'resume', 'finish', 'discard'))
);

alter table public.recorded_route_events enable row level security;

drop policy if exists recorded_route_events_select on public.recorded_route_events;
create policy recorded_route_events_select on public.recorded_route_events
  for select to authenticated
  using (
    exists (
      select 1 from public.recorded_routes r
      where r.id = recorded_route_events.recorded_route_id and r.owner_id = auth.uid()
    )
  );

drop policy if exists recorded_route_events_insert on public.recorded_route_events;
create policy recorded_route_events_insert on public.recorded_route_events
  for insert to authenticated
  with check (
    exists (
      select 1 from public.recorded_routes r
      where r.id = recorded_route_events.recorded_route_id and r.owner_id = auth.uid()
    )
  );

revoke all on table public.recorded_route_events from public, anon;
grant select on table public.recorded_route_events to authenticated;
grant insert (recorded_route_id) on table public.recorded_route_events to authenticated;
grant insert (seq) on table public.recorded_route_events to authenticated;
grant insert (event_type) on table public.recorded_route_events to authenticated;
grant insert (occurred_at) on table public.recorded_route_events to authenticated;

-- ---------------------------------------------------------------------------
-- 7. finalize_recorded_route(uuid) -- the only path that can mark a
--    recording 'completed' or write any derived column.
--
-- SECURITY DEFINER is a real, justified need here, not a default choice:
-- `authenticated` deliberately has no grant on recorded_routes'
-- derived columns or on setting status='completed' (see the trigger and
-- grants above) -- exactly the same reasoning
-- delete_message_for_everyone already uses for the same kind of gap
-- (authenticated lacking a grant that only a definer function can cross).
-- Ownership is still re-verified inside the function itself (auth.uid(),
-- not a trusted argument), so this is not a broad escalation -- it can
-- only ever act on a row already owned by the caller. No dynamic SQL
-- anywhere in this function -- every value is bound through a typed
-- plpgsql variable, never string-concatenated, so SQL injection through
-- this function is not possible.
--
-- Idempotent by design: our sync is retry-based, so a client that never
-- received the response to a successful call must be able to safely
-- call this again. If the route is already 'completed', this returns
-- the existing row as-is instead of erroring or recomputing -- a retry
-- after a dropped response is always safe. Only 'recording'/'paused'
-- trigger real (re-)computation; 'discarded' is still rejected (nothing
-- to finalize).
--
-- Explicit 0/1/2+ point handling (this review's main correctness fix):
-- ST_Envelope degrades to a POINT for a single/all-coincident point and
-- to a LINESTRING for a perfectly vertical/horizontal set -- bounding_box
-- is declared geography(Geometry,4326) (see the column comment) so any
-- of those is a valid value, but simplified_geometry stays LineString-
-- only, so a line is only ever built when there are 2+ points to make
-- one out of.
--
-- Duplicate-event-safe pause accounting: pause/resume events are
-- collapsed to drop consecutive duplicates of the same type (a repeated
-- pause with no intervening resume, or vice versa) before pairing them
-- -- without this, a duplicate pause event independently re-counted its
-- own "time to next event", double-counting the same paused interval.
--
-- MVP-simple, explicitly not over-engineered, per instruction:
--   - Distance: sums consecutive-point geography distances, skipping a
--     pair only when the implied speed exceeds 70 m/s (~252 km/h) -- one
--     fixed, generous threshold across all transport modes, not tuned
--     per mode. Revisit post-MVP.
--   - Elevation gain/loss: a naive positive/negative delta sum over raw
--     altitude_m with no smoothing -- will overcount on noisy GPS
--     altitude. Documented as a known MVP limitation, not fixed here.
--   - simplified_geometry: the FULL point-derived LineString when there
--     are 2+ points, not actually simplified yet. A tolerance-based
--     reduction (e.g. Douglas-Peucker) needs a metric projection to use
--     a meaningful meter-based tolerance; doing that with an unverified
--     transform in this same pass was judged riskier than shipping an
--     honestly unsimplified (but correct) line and deferring real
--     simplification to a later phase.
--   - A missing finish/discard event (abandoned recording) uses now()
--     as the effective finish time -- this is also how recovery closes
--     out an unfinished recording.
--   - Long GPS-signal-loss gaps are currently counted as moving time
--     (not specially detected) -- flagged as an open tuning decision in
--     the GPS design review, not resolved here.
--   - paused_s is clamped to >= 0 as a final safety net against
--     corrupt/out-of-order client timestamps (belt-and-suspenders with
--     the table's own paused_time_s >= 0 CHECK constraint, which would
--     otherwise turn a timestamp bug into a hard failure instead of a
--     graceful best-effort value).
-- Raw route_points/recorded_route_events are only ever read here, never
-- written or mutated.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_recorded_route(p_recorded_route_id uuid)
returns public.recorded_routes
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare
  route public.recorded_routes;
  v_start_at timestamptz;
  v_finish_at timestamptz;
  v_paused_s numeric := 0;
  v_distance double precision := 0;
  v_moving_s double precision;
  v_avg_speed double precision;
  v_max_speed double precision;
  v_min_alt double precision;
  v_max_alt double precision;
  v_gain double precision := 0;
  v_loss double precision := 0;
  v_bbox geography;
  v_geom geography;
  v_seg_distance double precision;
  v_seg_seconds double precision;
  v_alt_diff double precision;
  v_prev_alt double precision;
  v_point_count integer;
  rec record;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select * into route from public.recorded_routes
  where id = p_recorded_route_id and owner_id = auth.uid()
  for update;

  if not found then
    raise exception 'recorded route not found or access denied' using errcode = '42501';
  end if;

  -- Idempotent retry: already finalized, hand back the existing result
  -- rather than erroring or recomputing.
  if route.status = 'completed' then
    return route;
  end if;

  if route.status not in ('recording', 'paused') then
    raise exception 'recorded route is not in a finalizable state (status=%)', route.status
      using errcode = '55000';
  end if;

  select min(occurred_at) into v_start_at
  from public.recorded_route_events
  where recorded_route_id = p_recorded_route_id and event_type = 'start';

  if v_start_at is null then
    raise exception 'recorded route has no start event' using errcode = '55000';
  end if;

  select max(occurred_at) into v_finish_at
  from public.recorded_route_events
  where recorded_route_id = p_recorded_route_id and event_type in ('finish', 'discard');

  -- finalize is also how an abandoned/never-explicitly-finished
  -- recording gets closed out on recovery.
  if v_finish_at is null then
    v_finish_at := now();
  end if;

  -- Pause accounting, duplicate-safe: collapse consecutive same-type
  -- pause/resume events (a repeated pause or resume with nothing in
  -- between is a no-op) before pairing pause -> next-resume-or-finish.
  with pause_resume_only as (
    select event_type, occurred_at, seq,
           lag(event_type) over (order by seq) as prev_type
    from public.recorded_route_events
    where recorded_route_id = p_recorded_route_id
      and event_type in ('pause', 'resume')
  ),
  collapsed as (
    select event_type, occurred_at, seq
    from pause_resume_only
    where prev_type is distinct from event_type
  ),
  ordered_events as (
    select event_type, occurred_at,
           lead(event_type) over (order by seq) as next_type,
           lead(occurred_at) over (order by seq) as next_at
    from collapsed
  )
  select coalesce(sum(
    extract(epoch from (
      case when next_type = 'resume' then next_at else v_finish_at end - occurred_at
    ))
  ), 0)
  into v_paused_s
  from ordered_events
  where event_type = 'pause';

  v_paused_s := greatest(v_paused_s, 0);

  select count(*) into v_point_count
  from public.route_points
  where recorded_route_id = p_recorded_route_id;

  if v_point_count > 0 then
    for rec in
      select position, altitude_m, speed_mps, recorded_at,
             lag(position) over (order by seq) as prev_position,
             lag(recorded_at) over (order by seq) as prev_recorded_at
      from public.route_points
      where recorded_route_id = p_recorded_route_id
      order by seq
    loop
      if rec.prev_position is not null then
        v_seg_distance := st_distance(rec.prev_position, rec.position);
        v_seg_seconds := extract(epoch from (rec.recorded_at - rec.prev_recorded_at));
        if v_seg_seconds > 0 and (v_seg_distance / v_seg_seconds) <= 70 then
          v_distance := v_distance + v_seg_distance;
        end if;
      end if;

      if rec.altitude_m is not null then
        v_min_alt := least(coalesce(v_min_alt, rec.altitude_m), rec.altitude_m);
        v_max_alt := greatest(coalesce(v_max_alt, rec.altitude_m), rec.altitude_m);
        if v_prev_alt is not null then
          v_alt_diff := rec.altitude_m - v_prev_alt;
          if v_alt_diff > 0 then
            v_gain := v_gain + v_alt_diff;
          else
            v_loss := v_loss + abs(v_alt_diff);
          end if;
        end if;
        v_prev_alt := rec.altitude_m;
      end if;

      if rec.speed_mps is not null then
        v_max_speed := greatest(coalesce(v_max_speed, rec.speed_mps), rec.speed_mps);
      end if;
    end loop;

    if v_point_count = 1 then
      -- A single point has no meaningful line. Its envelope is itself,
      -- which bounding_box's untyped-subtype geography column can
      -- safely store; simplified_geometry stays NULL.
      select position::geography into v_bbox
      from public.route_points
      where recorded_route_id = p_recorded_route_id;
      v_geom := null;
    else
      -- 2+ points: safe to build both. ST_Envelope may still degenerate
      -- to a POINT or LINESTRING if every point is coincident or
      -- perfectly co-linear on one axis -- bounding_box's column type
      -- accepts any of those, deliberately.
      select
        st_envelope(st_collect(position::geometry))::geography,
        st_makeline(position::geometry order by seq)::geography
      into v_bbox, v_geom
      from public.route_points
      where recorded_route_id = p_recorded_route_id;
    end if;
  end if;
  -- v_point_count = 0: v_bbox and v_geom stay NULL, v_distance stays 0,
  -- altitude/speed extremes stay NULL -- all already their declared
  -- initial/default values, nothing further to do.

  v_moving_s := greatest(extract(epoch from (v_finish_at - v_start_at)) - v_paused_s, 0);
  if v_moving_s > 0 then
    v_avg_speed := v_distance / v_moving_s;
  end if;

  update public.recorded_routes set
    status = 'completed',
    ended_at = v_finish_at,
    total_distance_m = v_distance,
    elapsed_time_s = round(extract(epoch from (v_finish_at - v_start_at)))::integer,
    paused_time_s = round(v_paused_s)::integer,
    moving_time_s = round(v_moving_s)::integer,
    avg_speed_mps = v_avg_speed,
    max_speed_mps = v_max_speed,
    min_altitude_m = v_min_alt,
    max_altitude_m = v_max_alt,
    elevation_gain_m = v_gain,
    elevation_loss_m = v_loss,
    bounding_box = v_bbox,
    simplified_geometry = v_geom,
    updated_at = now()
  where id = p_recorded_route_id
  returning * into route;

  return route;
end;
$$;

revoke all on function public.finalize_recorded_route(uuid) from public, anon;
grant execute on function public.finalize_recorded_route(uuid) to authenticated;
