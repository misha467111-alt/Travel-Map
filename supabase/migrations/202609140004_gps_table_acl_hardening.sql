-- EMERGENCY FOLLOW-UP: GPS-1 table ACL hardening.
--
-- Fixes the live gap found during GPS-1 post-apply verification:
-- 202609140002_trips_gps_core.sql's table-level revoke statements
-- (`revoke all on table public.<t> from public, anon;`) omitted
-- `authenticated`. This project's public schema has a default ACL
-- (confirmed via pg_default_acl) that grants anon/authenticated/
-- service_role full privileges -- including TRUNCATE -- on every newly
-- created table, unless explicitly revoked. Every other table in this
-- schema (confirmed via check_ins) revokes this default from
-- `authenticated` before re-granting narrowly; GPS-1's five new tables
-- did not, leaving `authenticated` with the full unrevoked default:
-- TRUNCATE on all five tables, plus INSERT/UPDATE on identity and
-- derived columns that were never meant to be client-writable (RLS and
-- the protect_*_system_fields triggers independently still blocked the
-- exploitable consequences of the latter -- owner_id could not actually
-- be changed, derived stats could not actually be written, invalid
-- status transitions were still rejected -- but TRUNCATE bypasses RLS
-- entirely and depends only on table privilege, so it was a real,
-- live, exploitable gap).
--
-- This migration changes ONLY table-level grants on the five GPS-1
-- tables. It does not touch RLS policies, table schemas, functions,
-- triggers, enums, indexes, or any other object. Every grant re-applied
-- below is copied verbatim from 202609140002_trips_gps_core.sql's own
-- grant statements -- nothing broader, nothing narrower.

-- ---------------------------------------------------------------------------
-- trips
-- ---------------------------------------------------------------------------
revoke all on table public.trips from public, anon, authenticated;

grant select, delete on table public.trips to authenticated;
grant insert (title), update (title) on table public.trips to authenticated;
grant insert (description), update (description) on table public.trips to authenticated;
grant insert (status), update (status) on table public.trips to authenticated;
grant insert (visibility), update (visibility) on table public.trips to authenticated;
grant insert (started_at), update (started_at) on table public.trips to authenticated;
grant insert (ended_at), update (ended_at) on table public.trips to authenticated;
grant insert (cover_photo_ref), update (cover_photo_ref) on table public.trips to authenticated;
-- owner_id/id/created_at/updated_at: no grant, as originally intended.

-- ---------------------------------------------------------------------------
-- recorded_routes
-- ---------------------------------------------------------------------------
revoke all on table public.recorded_routes from public, anon, authenticated;

grant select, delete on table public.recorded_routes to authenticated;
grant insert (id) on table public.recorded_routes to authenticated;
grant insert (title), update (title) on table public.recorded_routes to authenticated;
grant insert (trip_id), update (trip_id) on table public.recorded_routes to authenticated;
grant insert (transport_mode), update (transport_mode) on table public.recorded_routes to authenticated;
grant update (status) on table public.recorded_routes to authenticated;
grant insert (visibility), update (visibility) on table public.recorded_routes to authenticated;
grant insert (started_at) on table public.recorded_routes to authenticated;
-- owner_id: no grant (client may never choose it). ended_at and every
-- derived column: no grant (writable only inside finalize_recorded_route,
-- which runs as the function owner, not as authenticated). status: no
-- INSERT grant (the protect_recorded_route_system_fields trigger forces
-- 'recording' at creation regardless); UPDATE only, still gated by that
-- same trigger's transition allow-list and its 'completed' block.

-- ---------------------------------------------------------------------------
-- route_points
-- ---------------------------------------------------------------------------
revoke all on table public.route_points from public, anon, authenticated;

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
-- No UPDATE, no DELETE, no TRUNCATE grant -- raw samples are immutable
-- and append-only; removal only via ON DELETE CASCADE from the parent.

-- ---------------------------------------------------------------------------
-- route_waypoints
-- ---------------------------------------------------------------------------
revoke all on table public.route_waypoints from public, anon, authenticated;

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
-- owner_id/id/recorded_route_id/position/altitude_m/recorded_at/
-- created_at/updated_at: no UPDATE grant -- telemetry/identity is
-- immutable once recorded, only title/note/waypoint_type/photo_ref are
-- editable, matching the original design exactly. No TRUNCATE grant.

-- ---------------------------------------------------------------------------
-- recorded_route_events
-- ---------------------------------------------------------------------------
revoke all on table public.recorded_route_events from public, anon, authenticated;

grant select on table public.recorded_route_events to authenticated;
grant insert (recorded_route_id) on table public.recorded_route_events to authenticated;
grant insert (seq) on table public.recorded_route_events to authenticated;
grant insert (event_type) on table public.recorded_route_events to authenticated;
grant insert (occurred_at) on table public.recorded_route_events to authenticated;
-- No UPDATE, no DELETE, no TRUNCATE grant -- append-only lifecycle log.
