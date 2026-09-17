-- GPS SYNC PHASE 3B -- backend contract for the future Flutter sync
-- engine: two batch-upload RPCs (route_points, recorded_route_events)
-- plus a server-side terminal-route write guard.
--
-- Design-only until reviewed: this migration is NOT applied by this
-- change. Not deployed to production. No Flutter sync engine exists yet
-- to call these functions.
--
-- Confirmed by re-reading 202609140002_trips_gps_core.sql and
-- 202609140004_gps_table_acl_hardening.sql (not assumed) before writing
-- this migration:
--   - recorded_routes.id and route_waypoints.id are already client-
--     generated UUIDs with no server default; route_points and
--     recorded_route_events already use a client-supplied, per-route
--     monotonic `seq` as (part of) their primary key. No local<->server
--     ID mapping is introduced or needed here.
--   - `authenticated` already holds a direct, column-scoped INSERT grant
--     on both route_points and recorded_route_events (see
--     202609140004, "route_points"/"recorded_route_events" sections).
--     This means an RPC-only integrity check would be bypassable by a
--     client calling the table directly -- the terminal-route write
--     guard below is therefore implemented as a BEFORE INSERT trigger on
--     both tables, not merely inside the two RPCs, so it is the single
--     enforcement point regardless of which path a client uses.
--   - recorded_routes.status is constrained to exactly
--     ('recording', 'paused', 'completed', 'discarded')
--     (recorded_routes_status_check). 'completed' and 'discarded' are
--     both terminal for this guard's purposes -- matches
--     protect_recorded_route_system_fields' own existing terminal
--     handling of these same two values.
--   - finalize_recorded_route(uuid) takes a `for update` lock on the
--     recorded_routes row for the duration of its computation. Both new
--     RPCs below take a `for share` lock on the same row before doing
--     any work, which Postgres will queue behind a concurrent `for
--     update` (and vice versa) -- this serializes sync_route_points/
--     sync_route_events against a concurrent finalize_recorded_route
--     call on the same route, closing the race where new points could
--     otherwise be accepted while finalize is mid-computation.
--   - Neither new RPC references activity_events, _record_activity_event,
--     or public.profiles.xp anywhere. ROUTE_RECORDED_COMPLETED remains
--     inactive / 0 XP, exactly as before this migration. That wiring is
--     explicitly deferred to a future phase (see the Phase 3A report).
--
-- Contract corrections applied (both required by explicit review
-- feedback on an earlier draft of this migration, not optional):
--   1. Neither RPC uses a naive `insert ... on conflict do nothing
--      returning max(seq)` shape. That shape can silently accept a
--      submitted row whose payload differs from an already-persisted row
--      at the same (recorded_route_id, seq) -- DO NOTHING means the
--      conflicting *existing* row wins with no signal to the caller, and
--      the caller's cursor would then advance past data it never
--      actually confirmed. Both RPCs instead validate the entire
--      submitted batch first (structural validity, uniqueness of seq
--      within the batch, and an explicit field-by-field comparison of
--      every submitted row against any existing row at the same seq) and
--      RAISE, aborting the whole call with nothing written, if any
--      submitted row conflicts with different persisted data. Only after
--      every row in the batch is confirmed either new or identical to
--      what is already persisted does the function insert the rows that
--      were actually new. No exception handler catches or swallows
--      that raise anywhere in either function, so an uncaught exception
--      always rolls back every write already made earlier in the same
--      call -- "one bad row in the batch" therefore always yields zero
--      new rows from that call, not a partial insert.
--   2. The terminal-route write guard (BEFORE INSERT trigger on both
--      route_points and recorded_route_events) did not exist before this
--      migration. It is intentionally table-level, not RPC-level, for
--      the bypass reason explained above.
--
-- Backward compatibility: no existing table, column, index, RLS policy,
-- grant, enum, or the finalize_recorded_route function itself is altered
-- by this migration. Every legitimate write that worked before this
-- migration (direct authenticated INSERT into route_points/
-- recorded_route_events while the parent route is 'recording' or
-- 'paused') still works identically after it; only inserts against an
-- already-'completed'/'discarded' parent are newly rejected, which was
-- never a supported/desired write before either.

-- ---------------------------------------------------------------------------
-- 1. Terminal-route write guard.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_recorded_route_not_terminal()
returns trigger
language plpgsql
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.recorded_routes
  where id = new.recorded_route_id;

  if v_status is null then
    -- Either the parent truly doesn't exist (the FK constraint will
    -- report that on its own once this trigger returns) or it exists but
    -- RLS hides it from the caller because they don't own it -- both
    -- cases are correctly blocked either way; this just gives an earlier,
    -- clearer signal than waiting on the FK check.
    raise exception 'recorded route % does not exist or access denied', new.recorded_route_id
      using errcode = '42501';
  end if;

  if v_status in ('completed', 'discarded') then
    raise exception 'cannot insert into % for a % recorded route', tg_table_name, v_status
      using errcode = '55000';
  end if;

  return new;
end
$$;

revoke all on function public.enforce_recorded_route_not_terminal() from public, anon, authenticated;

drop trigger if exists route_points_enforce_not_terminal on public.route_points;
create trigger route_points_enforce_not_terminal
before insert on public.route_points
for each row execute function public.enforce_recorded_route_not_terminal();

drop trigger if exists recorded_route_events_enforce_not_terminal on public.recorded_route_events;
create trigger recorded_route_events_enforce_not_terminal
before insert on public.recorded_route_events
for each row execute function public.enforce_recorded_route_not_terminal();

-- ---------------------------------------------------------------------------
-- 2. sync_route_points -- atomic, idempotent batch upload of route_points.
--
-- SECURITY INVOKER (not DEFINER): the existing route_points_insert RLS
-- policy already permits exactly the operation this function performs
-- for the owning user (insert rows whose recorded_route_id belongs to a
-- recorded_routes row owned by auth.uid()) -- there is no privilege gap
-- here of the kind that justified finalize_recorded_route's DEFINER (that
-- one writes columns `authenticated` has no grant on at all). Running as
-- invoker means RLS and the terminal-route trigger both apply to this
-- function's own INSERT exactly as they would to a direct client INSERT,
-- which is deliberate defense in depth, not an oversight.
--
-- Per-point payload fields (matches the local Drift LocalRoutePoints
-- columns 1:1, minus recorded_route_id and ownerId, which are not
-- per-row here -- recorded_route_id is the function's own parameter, so
-- every row in a single call targets exactly one route by construction):
--   seq, latitude, longitude, altitude_m, horizontal_accuracy_m,
--   vertical_accuracy_m, speed_mps, speed_accuracy_mps, heading_deg,
--   heading_accuracy_deg, recorded_at, provider
--
-- Coordinate bounds (latitude in [-90,90], longitude in [-180,180]) are
-- validated explicitly here because nothing else would catch an
-- out-of-range value: geography(Point,4326) accepts any coordinate ST_
-- MakePoint hands it without complaint. No other field gets bespoke
-- validation beyond what the table's own CHECK constraints already
-- enforce (heading_deg range, seq > 0, non-negative accuracies/speeds) --
-- those are reached naturally through the INSERT at the end and are not
-- duplicated here, to avoid inventing stricter rules than the schema
-- already has.
--
-- Return value: the highest `seq` from the SUBMITTED batch that is, by
-- the time this function returns success, confirmed persisted with
-- exactly the submitted data (either freshly inserted, or already
-- present and byte-for-byte identical). Never the table's global max(seq)
-- -- a caller with a stale/incomplete local batch must never be told a
-- seq it did not actually submit is now safely synced. The caller is
-- responsible for submitting a contiguous, cursor-bounded batch (the
-- local Drift design already guarantees this: `seq` is assigned
-- gapless, one at a time, per route); this function does not itself
-- verify contiguity against seq values outside the submitted batch, since
-- it has no visibility into the caller's own local cursor state.
-- ---------------------------------------------------------------------------
create or replace function public.sync_route_points(
  p_recorded_route_id uuid,
  p_points jsonb
)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_route public.recorded_routes;
  v_batch_count integer;
  v_distinct_seq_count integer;
  v_invalid_count integer;
  v_conflict_count integer;
  v_max_batch_seq integer;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_points is null or jsonb_typeof(p_points) is distinct from 'array' then
    raise exception 'p_points must be a JSON array' using errcode = '22023';
  end if;

  -- `for share`: deliberately not `for update` (this function never
  -- writes the route row itself) -- see the file header for why this
  -- still serializes against a concurrent finalize_recorded_route call.
  select * into v_route
  from public.recorded_routes
  where id = p_recorded_route_id and owner_id = auth.uid()
  for share;

  if not found then
    raise exception 'recorded route not found or access denied' using errcode = '42501';
  end if;

  if v_route.status in ('completed', 'discarded') then
    raise exception 'recorded route is not accepting new points (status=%)', v_route.status
      using errcode = '55000';
  end if;

  select count(*), count(distinct seq)
  into v_batch_count, v_distinct_seq_count
  from jsonb_to_recordset(p_points) as t(seq integer);

  if v_batch_count = 0 then
    raise exception 'p_points must be a non-empty JSON array' using errcode = '22023';
  end if;

  if v_distinct_seq_count <> v_batch_count then
    raise exception 'duplicate seq values within submitted point batch' using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from jsonb_to_recordset(p_points) as t(
    seq integer, latitude double precision, longitude double precision, recorded_at timestamptz
  )
  where t.seq is null or t.seq <= 0
     or t.latitude is null or t.latitude < -90 or t.latitude > 90
     or t.longitude is null or t.longitude < -180 or t.longitude > 180
     or t.recorded_at is null;

  if v_invalid_count > 0 then
    raise exception
      'invalid point in batch: seq must be > 0, latitude in [-90,90], longitude in [-180,180], recorded_at required'
      using errcode = '22023';
  end if;

  -- Conflicting-retry detection: every submitted seq that already has a
  -- persisted row must match it in every field, or the whole call fails.
  -- Comparing longitude/latitude back out of the stored geography is
  -- exact here (no reprojection ever happens -- both sides are SRID 4326
  -- the whole way through), so this is a safe direct comparison, not an
  -- approximate one.
  select count(*) into v_conflict_count
  from jsonb_to_recordset(p_points) as t(
    seq integer, latitude double precision, longitude double precision,
    altitude_m double precision, horizontal_accuracy_m double precision,
    vertical_accuracy_m double precision, speed_mps double precision,
    speed_accuracy_mps double precision, heading_deg double precision,
    heading_accuracy_deg double precision, recorded_at timestamptz, provider text
  )
  join public.route_points rp
    on rp.recorded_route_id = p_recorded_route_id and rp.seq = t.seq
  where st_x(rp.position::geometry) is distinct from t.longitude
     or st_y(rp.position::geometry) is distinct from t.latitude
     or rp.altitude_m is distinct from t.altitude_m
     or rp.horizontal_accuracy_m is distinct from t.horizontal_accuracy_m
     or rp.vertical_accuracy_m is distinct from t.vertical_accuracy_m
     or rp.speed_mps is distinct from t.speed_mps
     or rp.speed_accuracy_mps is distinct from t.speed_accuracy_mps
     or rp.heading_deg is distinct from t.heading_deg
     or rp.heading_accuracy_deg is distinct from t.heading_accuracy_deg
     or rp.recorded_at is distinct from t.recorded_at
     or rp.provider is distinct from t.provider;

  if v_conflict_count > 0 then
    raise exception
      'point batch conflicts with already-persisted data for one or more seq values'
      using errcode = '23505';
  end if;

  -- Only rows genuinely new (no existing row at this seq) are inserted --
  -- rows already present and identical are silently skipped, which is
  -- exactly the idempotent-retry behavior this function promises. This
  -- INSERT is still independently subject to the route_points_insert RLS
  -- policy and the terminal-route trigger above, exactly as a direct
  -- client INSERT would be (SECURITY INVOKER).
  insert into public.route_points (
    recorded_route_id, seq, position, altitude_m, horizontal_accuracy_m,
    vertical_accuracy_m, speed_mps, speed_accuracy_mps, heading_deg,
    heading_accuracy_deg, recorded_at, provider
  )
  select
    p_recorded_route_id,
    t.seq,
    st_setsrid(st_makepoint(t.longitude, t.latitude), 4326)::geography,
    t.altitude_m, t.horizontal_accuracy_m, t.vertical_accuracy_m,
    t.speed_mps, t.speed_accuracy_mps, t.heading_deg, t.heading_accuracy_deg,
    t.recorded_at, t.provider
  from jsonb_to_recordset(p_points) as t(
    seq integer, latitude double precision, longitude double precision,
    altitude_m double precision, horizontal_accuracy_m double precision,
    vertical_accuracy_m double precision, speed_mps double precision,
    speed_accuracy_mps double precision, heading_deg double precision,
    heading_accuracy_deg double precision, recorded_at timestamptz, provider text
  )
  where not exists (
    select 1 from public.route_points rp
    where rp.recorded_route_id = p_recorded_route_id and rp.seq = t.seq
  );

  select max(t.seq) into v_max_batch_seq
  from jsonb_to_recordset(p_points) as t(seq integer);

  return v_max_batch_seq;
end;
$$;

revoke all on function public.sync_route_points(uuid, jsonb) from public, anon;
grant execute on function public.sync_route_points(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. sync_route_events -- atomic, idempotent batch upload of
--    recorded_route_events. Same contract shape as sync_route_points,
--    without the geography-construction/coordinate-bounds concerns.
--
-- Per-event payload fields (matches local LocalRouteEvents columns 1:1,
-- minus recorded_route_id/ownerId, same reasoning as sync_route_points):
--   seq, event_type, occurred_at
--
-- event_type's allowed vocabulary is taken verbatim from the existing
-- recorded_route_events_type_check constraint -- not re-derived or
-- guessed.
-- ---------------------------------------------------------------------------
create or replace function public.sync_route_events(
  p_recorded_route_id uuid,
  p_events jsonb
)
returns integer
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_route public.recorded_routes;
  v_batch_count integer;
  v_distinct_seq_count integer;
  v_invalid_count integer;
  v_conflict_count integer;
  v_max_batch_seq integer;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_events is null or jsonb_typeof(p_events) is distinct from 'array' then
    raise exception 'p_events must be a JSON array' using errcode = '22023';
  end if;

  select * into v_route
  from public.recorded_routes
  where id = p_recorded_route_id and owner_id = auth.uid()
  for share;

  if not found then
    raise exception 'recorded route not found or access denied' using errcode = '42501';
  end if;

  if v_route.status in ('completed', 'discarded') then
    raise exception 'recorded route is not accepting new events (status=%)', v_route.status
      using errcode = '55000';
  end if;

  select count(*), count(distinct seq)
  into v_batch_count, v_distinct_seq_count
  from jsonb_to_recordset(p_events) as t(seq integer);

  if v_batch_count = 0 then
    raise exception 'p_events must be a non-empty JSON array' using errcode = '22023';
  end if;

  if v_distinct_seq_count <> v_batch_count then
    raise exception 'duplicate seq values within submitted event batch' using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from jsonb_to_recordset(p_events) as t(
    seq integer, event_type text, occurred_at timestamptz
  )
  where t.seq is null or t.seq <= 0
     or t.event_type is null
     or t.event_type not in ('start', 'pause', 'resume', 'finish', 'discard')
     or t.occurred_at is null;

  if v_invalid_count > 0 then
    raise exception
      'invalid event in batch: seq must be > 0, event_type must be one of start/pause/resume/finish/discard, occurred_at required'
      using errcode = '22023';
  end if;

  select count(*) into v_conflict_count
  from jsonb_to_recordset(p_events) as t(seq integer, event_type text, occurred_at timestamptz)
  join public.recorded_route_events re
    on re.recorded_route_id = p_recorded_route_id and re.seq = t.seq
  where re.event_type is distinct from t.event_type
     or re.occurred_at is distinct from t.occurred_at;

  if v_conflict_count > 0 then
    raise exception
      'event batch conflicts with already-persisted data for one or more seq values'
      using errcode = '23505';
  end if;

  insert into public.recorded_route_events (recorded_route_id, seq, event_type, occurred_at)
  select p_recorded_route_id, t.seq, t.event_type, t.occurred_at
  from jsonb_to_recordset(p_events) as t(seq integer, event_type text, occurred_at timestamptz)
  where not exists (
    select 1 from public.recorded_route_events re
    where re.recorded_route_id = p_recorded_route_id and re.seq = t.seq
  );

  select max(t.seq) into v_max_batch_seq
  from jsonb_to_recordset(p_events) as t(seq integer);

  return v_max_batch_seq;
end;
$$;

revoke all on function public.sync_route_events(uuid, jsonb) from public, anon;
grant execute on function public.sync_route_events(uuid, jsonb) to authenticated;
