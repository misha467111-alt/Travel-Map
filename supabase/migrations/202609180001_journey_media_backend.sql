-- JOURNEY PHASE 1H-E1 -- remote Journey media backend contract.
--
-- Adds the metadata table `route_media` and the PRIVATE Storage bucket
-- `journey_media` that the later client sync (Phase 1H-E2) will use. No RPC
-- and no Edge Function: media is low-volume like route_waypoints, so direct
-- table access under RLS + a validating trigger is sufficient.
--
-- Verified against the LIVE project before writing (read-only catalog
-- queries): all 24 prior migrations are applied; storage buckets are only
-- `avatars` and `location_images` (both public); no `route_media` exists;
-- `authenticated` holds DELETE on recorded_routes/route_waypoints (so a
-- remote route CAN be deleted via the API -- see "Orphans" below).
--
-- DESIGN DECISIONS
--
-- 1. No `storage_path` column. The object path is fully determined by three
--    immutable ids:
--        <owner_id>/<recorded_route_id>/<id>.jpg      (bucket journey_media)
--    Storing it would be redundant derived state that could drift from
--    those ids. The Storage INSERT policy below enforces exactly that shape
--    (owner folder, an owned route, a lowercase-UUID .jpg filename), so the
--    path is the contract without a column. Revisit only if a concrete need
--    that derivation cannot meet appears.
--
-- 2. No `updated_at`, and the row is immutable after INSERT for ALL roles.
--    The only lifecycle operations are insert and delete. Three independent
--    layers enforce it: (a) no UPDATE/TRUNCATE privilege for any ordinary
--    role -- service_role included, whose default ALL privilege and
--    BYPASSRLS made it the gap in the first draft (see section 4); (b) no
--    UPDATE policy; (c) a BEFORE UPDATE trigger that rejects UPDATE for every
--    role (including the UPDATE branch of INSERT ... ON CONFLICT DO UPDATE).
--    The columns that determine the Storage path -- id, owner_id,
--    recorded_route_id -- can therefore not be changed after creation.
--
-- 3. Relational integrity is enforced by triggers, not RLS alone, so it
--    also holds for any non-RLS writer. At INSERT: the row's owner must be
--    the owner of its recorded route, and a non-null waypoint must belong to
--    the SAME recorded route and the SAME owner. For the LIFETIME of the row
--    (see "LIFETIME INVARIANT" below): the parent identity those checks rely
--    on can never change.
--
--    EXISTING-TABLE IMPACT (the only one): this migration adds two small
--    BEFORE UPDATE identity-guard triggers (and their functions) on
--    public.recorded_routes and public.route_waypoints. No column, grant,
--    policy, constraint or data of either table is changed, and legitimate
--    updates (status, finalization/derived fields, title, note, sync
--    lifecycle fields) are unaffected. A plain FK on waypoint_id alone
--    cannot express "same route"; a composite FK would need new unique
--    constraints on the existing tables, which is the broader change this
--    migration deliberately avoids.
--
-- LIFETIME INVARIANT (parent identity guards + locking)
--    Before: service_role (full default UPDATE, BYPASSRLS) and the table
--    owner could UPDATE recorded_routes.owner_id, or route_waypoints.owner_id
--    or recorded_route_id (the existing protect triggers only inspect
--    `authenticated`), leaving route_media pointing at a re-homed parent and
--    exposing it to the NEW owner's cascade deletes. Now those identity
--    columns are unconditionally immutable for every role, so every
--    relationship validated at media INSERT stays true for as long as the
--    row exists.
--    Why this closes the race: the guard is unconditional, not "only when
--    media exists", so there is no check-then-act window -- no interleaving
--    of a media INSERT with a parent UPDATE can leave an invalid
--    relationship, because the parent UPDATE of an identity column fails
--    whenever it runs. (A conditional guard would be racy: an owner_id UPDATE
--    takes FOR NO KEY UPDATE, which does not conflict with the foreign key's
--    FOR KEY SHARE.) The remaining interleaving is a parent DELETE, or
--    delete-and-recreate under the same client-chosen id, between the
--    validation read and the foreign-key check: the validation reads take
--    FOR KEY SHARE, which conflicts with DELETE, so the parent cannot
--    disappear until the media insert commits (the ON DELETE CASCADE then
--    removes the committed media consistently).
--    A deliberate repair that must change parent identity is an
--    administrative operation outside the application contract: disable the
--    guard trigger in a reviewed migration as the table owner. There is no
--    repair RPC and no service_role escape hatch.
--
-- 4. Terminal-route semantics. Media is synchronized after the LOCAL
--    Journey is completed but BEFORE finalize_recorded_route(), so the
--    remote route may still be 'recording' (or already terminal on a
--    retry). Therefore NOTHING here checks recorded_routes.status -- unlike
--    route_points/recorded_route_events, which carry the terminal-route
--    guard, route_waypoints (and now route_media) intentionally do not.
--
-- 5. Identity and retry contract (what is, and is NOT, guaranteed).
--    GUARANTEED by this migration: a media id maps deterministically to one
--    row (primary key) and one Storage path; a second INSERT of the same id
--    is rejected (23505). The bucket policies grant `authenticated` INSERT,
--    SELECT and DELETE only, so an authenticated in-place UPDATE/overwrite
--    of an object is not part of the contract; ordinary uploads are
--    expected to use upsert:false.
--    NOT guaranteed (do not infer it): that a duplicate id means the
--    existing row or object has the same content; that object bytes can
--    never change (DELETE followed by a new INSERT of the same path is a
--    separate, permitted operation); that the hosted Storage API rejects
--    `upsert: true` (the SQL shim in the behavior test proves the policy
--    shape, not the hosted service); or that "already exists" means a retry
--    succeeded. Phase 1H-E2 must reconcile database metadata and object
--    state before acknowledging a retry as synced.
--
-- DEFERRED DEBT -- ORPHANED STORAGE OBJECTS (F4)
--    ON DELETE CASCADE removes route_media ROWS only; it can never delete
--    Storage objects. authenticated users can delete their own
--    recorded_routes / route_waypoints through the API (verified live), and
--    account deletion cascades the same way, so objects can be left behind
--    with no row pointing at them. The shipped app has no route-delete
--    feature, and no requirement for a cleanup mechanism is demonstrated, so
--    NO Edge Function, scheduled job or cleanup worker is introduced here.
--    Reconciliation / account-deletion cleanup of orphaned objects is
--    explicitly FUTURE WORK. The client-driven path (local tombstone ->
--    delete row -> delete object) only covers deletions the app itself
--    performs.
--
-- DEFERRED DEFENCE-IN-DEPTH -- CONTENT VALIDATION (F5)
--    The bucket's `allowed_mime_types = image/jpeg` is a declared-type
--    allowlist, NOT content validation: it does not prove the bytes are a
--    valid or safe JPEG. The client normalizes images before upload, but that
--    is a client-side processing step, not a security boundary -- a hostile
--    authenticated client can upload any bytes within the declared type and
--    size limit into its own private namespace. Server-side content
--    validation is deferred; no media-processing backend is built here.

-- ---------------------------------------------------------------------------
-- 1. route_media
-- ---------------------------------------------------------------------------
create table public.route_media (
  id uuid primary key,
  recorded_route_id uuid not null
    references public.recorded_routes(id) on delete cascade,
  owner_id uuid not null
    references public.profiles(id) on delete cascade,
  waypoint_id uuid
    references public.route_waypoints(id) on delete cascade,
  media_type text not null default 'image',
  captured_at timestamptz not null,
  -- Standalone media only; media attached to a Moment inherits the
  -- Moment's telemetry and never carries its own position.
  position geography(Point, 4326),
  created_at timestamptz not null default now(),
  constraint route_media_media_type_check
    check (media_type in ('image')),
  constraint route_media_position_standalone_only
    check (waypoint_id is null or position is null)
);

create index route_media_route_captured_idx
  on public.route_media (recorded_route_id, captured_at, id);

-- Supports the waypoint ON DELETE CASCADE and per-Moment lookups.
create index route_media_waypoint_idx
  on public.route_media (waypoint_id)
  where waypoint_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Identity / integrity trigger
-- ---------------------------------------------------------------------------
create or replace function public.protect_route_media_system_fields()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_route_owner uuid;
begin
  -- UPDATE is rejected for EVERY role (service_role included). A row's
  -- id / owner_id / recorded_route_id / waypoint_id are what the Storage
  -- path <owner_id>/<recorded_route_id>/<id>.jpg is derived from, so none
  -- of them may ever change after INSERT. This also blocks the UPDATE half
  -- of INSERT ... ON CONFLICT DO UPDATE. (Table privileges below already
  -- deny UPDATE to every ordinary role; this trigger is the invariant that
  -- does not depend on grants or RLS. A deliberate repair would have to
  -- disable the trigger in a reviewed migration, as the table owner.)
  if tg_op = 'UPDATE' then
    raise exception 'route media is immutable once recorded'
      using errcode = '42501';
  end if;

  -- INSERT: never trust a client-supplied owner.
  if current_user = 'authenticated' then
    new.owner_id := auth.uid();
  end if;

  -- FOR KEY SHARE: hold the parent row against a concurrent DELETE (or
  -- delete-and-recreate under the same id) between this validation and the
  -- foreign-key check at the end of the statement. See "LIFETIME INVARIANT".
  select r.owner_id into v_route_owner
  from public.recorded_routes r
  where r.id = new.recorded_route_id
  for key share;

  if v_route_owner is null or v_route_owner is distinct from new.owner_id then
    raise exception 'recorded route % does not exist or is not owned by the media owner',
      new.recorded_route_id
      using errcode = '42501';
  end if;

  if new.waypoint_id is not null then
    perform 1
    from public.route_waypoints w
    where w.id = new.waypoint_id
      and w.recorded_route_id = new.recorded_route_id
      and w.owner_id = new.owner_id
    for key share;
    if not found then
      raise exception 'waypoint % does not belong to this recorded route and owner',
        new.waypoint_id
        using errcode = '42501';
    end if;
  end if;

  return new;
end
$$;

revoke all on function public.protect_route_media_system_fields()
  from public, anon, authenticated;

drop trigger if exists route_media_protect_system_fields on public.route_media;
create trigger route_media_protect_system_fields
before insert or update on public.route_media
for each row execute function public.protect_route_media_system_fields();

-- ---------------------------------------------------------------------------
-- 2b. Parent identity guards (the ONLY change to existing tables).
--
-- Unconditionally reject any change to the identity/relationship columns
-- that route_media relies on, for EVERY role (service_role and the table
-- owner included; no current_user test). Only identity columns are guarded:
--   recorded_routes : id, owner_id
--   route_waypoints : id, owner_id, recorded_route_id
-- Every other column stays exactly as mutable as before (status, derived
-- fields written by finalize_recorded_route(), title/note, sync fields).
-- The guard compares OLD and NEW, so an UPDATE that leaves the value
-- unchanged is still allowed. Plain (non column-list) BEFORE UPDATE
-- triggers, so ON CONFLICT DO UPDATE and every other UPDATE path are covered.
-- ---------------------------------------------------------------------------
create or replace function public.guard_recorded_route_identity()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $$
begin
  if new.id is distinct from old.id
     or new.owner_id is distinct from old.owner_id then
    raise exception 'recorded route identity (id, owner_id) is immutable'
      using errcode = '42501';
  end if;
  return new;
end
$$;

revoke all on function public.guard_recorded_route_identity()
  from public, anon, authenticated;

drop trigger if exists recorded_routes_identity_guard on public.recorded_routes;
create trigger recorded_routes_identity_guard
before update on public.recorded_routes
for each row execute function public.guard_recorded_route_identity();

create or replace function public.guard_route_waypoint_identity()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $$
begin
  if new.id is distinct from old.id
     or new.owner_id is distinct from old.owner_id
     or new.recorded_route_id is distinct from old.recorded_route_id then
    raise exception 'route waypoint identity (id, owner_id, recorded_route_id) is immutable'
      using errcode = '42501';
  end if;
  return new;
end
$$;

revoke all on function public.guard_route_waypoint_identity()
  from public, anon, authenticated;

drop trigger if exists route_waypoints_identity_guard on public.route_waypoints;
create trigger route_waypoints_identity_guard
before update on public.route_waypoints
for each row execute function public.guard_route_waypoint_identity();

-- ---------------------------------------------------------------------------
-- 3. RLS: select / insert / delete, owner only. No UPDATE policy.
-- ---------------------------------------------------------------------------
alter table public.route_media enable row level security;

drop policy if exists route_media_select on public.route_media;
create policy route_media_select on public.route_media
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists route_media_insert on public.route_media;
create policy route_media_insert on public.route_media
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and exists (
      select 1 from public.recorded_routes r
      where r.id = route_media.recorded_route_id
        and r.owner_id = (select auth.uid())
    )
    and (
      route_media.waypoint_id is null
      or exists (
        select 1 from public.route_waypoints w
        where w.id = route_media.waypoint_id
          and w.recorded_route_id = route_media.recorded_route_id
          and w.owner_id = (select auth.uid())
      )
    )
  );

drop policy if exists route_media_delete on public.route_media;
create policy route_media_delete on public.route_media
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 4. Grants (effective privileges, reviewed explicitly).
--
-- Supabase's DEFAULT PRIVILEGES (pg_default_acl, verified live) grant ALL
-- (arwdDxtm: insert/select/update/delete/truncate/references/trigger/
-- maintain) on every new public table to anon, authenticated AND
-- service_role. service_role also has BYPASSRLS, so RLS never constrains it.
-- Revoking only anon/authenticated would therefore leave service_role with
-- UPDATE and TRUNCATE. All four ordinary roles are revoked here, then
-- exactly the intended privileges are granted back:
--
--   role           SELECT  INSERT            DELETE  UPDATE  TRUNCATE
--   authenticated    yes   column-scoped      yes     NO      NO
--   service_role     yes   yes (validated)    yes     NO      NO
--   anon             NO    NO                 NO      NO      NO
--   public           NO    NO                 NO      NO      NO
--
-- (The table owner/superusers are outside this matrix; the UPDATE trigger
-- above still rejects UPDATE for them.) service_role INSERT is subject to
-- the same integrity trigger as everyone else.
-- ---------------------------------------------------------------------------
revoke all on table public.route_media
  from public, anon, authenticated, service_role;

grant select, insert, delete on table public.route_media to service_role;

grant select, delete on table public.route_media to authenticated;
grant insert (id) on table public.route_media to authenticated;
grant insert (recorded_route_id) on table public.route_media to authenticated;
grant insert (waypoint_id) on table public.route_media to authenticated;
grant insert (media_type) on table public.route_media to authenticated;
grant insert (captured_at) on table public.route_media to authenticated;
grant insert (position) on table public.route_media to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Private Storage bucket
-- ---------------------------------------------------------------------------
-- Private (public = false), JPEG only, 5 MB. The client uploads the
-- canonical normalized image (long edge <= ~1600 px, JPEG q80, EXIF
-- stripped), typically a few hundred KB; 5 MB is generous headroom and
-- half the other buckets' limit.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('journey_media', 'journey_media', false, 5242880, array['image/jpeg'])
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 6. Storage policies (INSERT / SELECT / DELETE only). No UPDATE policy is
--    granted to authenticated, so an authenticated in-place UPDATE of an
--    object is not part of the contract (see design note 5 for what this
--    does and does not guarantee).
--
-- Object name must be exactly:  <auth.uid()>/<owned recorded route id>/<uuid>.jpg
--   - segment 1 equals the caller's uid           (own namespace only)
--   - exactly two folder segments                 (no deeper nesting)
--   - segment 2 is a recorded route owned by the caller
--   - the file name is a lowercase UUID + ".jpg"  (the media id)
-- ---------------------------------------------------------------------------
drop policy if exists journey_media_owner_insert on storage.objects;
create policy journey_media_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'journey_media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 2
    and exists (
      select 1 from public.recorded_routes r
      where r.id::text = (storage.foldername(name))[2]
        and r.owner_id = (select auth.uid())
    )
    and storage.filename(name) ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
  );

drop policy if exists journey_media_owner_select on storage.objects;
create policy journey_media_owner_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'journey_media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists journey_media_owner_delete on storage.objects;
create policy journey_media_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'journey_media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
