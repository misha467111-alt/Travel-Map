-- PHASE 2.2A1 -- CREATE LOCATION UX v2 DATA-PATH PREPARATION
--
-- NOT APPLIED. Written and reviewed only, per explicit instruction.
--
-- Two changes, both additive to existing columns/constraints/tables that
-- already exist (supabase/migrations/202608290001_reference_filters_v2.sql
-- and 202608290003_location_details_metadata.sql):
--
-- 1. create_location_with_xp gains four optional trailing parameters
--    (p_address, p_amenities, p_opening_hours, p_timezone). This widens
--    the CURRENT LIVE 7-argument function (the one actually redefined in
--    202609040002_trusted_ai_location_moderation.sql -- NOT the original
--    baseline body) via DROP + CREATE, not a second overload. A second
--    overload would make the existing named-argument call from
--    LocationsRepository.createLocation ambiguous: Postgres resolves a
--    named call against every candidate whose supplied names all match
--    and whose omitted parameters all have defaults, and a second,
--    parallel 11-argument overload would be exactly such a candidate for
--    a call that only ever supplies the original 7 names -- Postgres
--    would then refuse the call as "not unique". Replacing the single
--    7-argument function in place with an 11-argument one (4 new
--    trailing optional params, all defaulting to null) leaves exactly
--    one function matching that call shape, so it stays unambiguous with
--    zero Flutter-side changes required for existing callers.
--
--    status='pending', moderation='pending', and the absence of any XP
--    award at creation are all preserved verbatim from the live body --
--    XP is only ever awarded later, atomically, by
--    record_location_moderation_result on approval (see
--    moderation_sql_contract_test.mjs's existing assertions, which this
--    migration does not touch).
--
--    The dead legacy 6-argument overload (service_role only since
--    202609040002) is untouched.
--
-- 2. A new, narrowly-scoped SECURITY DEFINER RPC,
--    cleanup_own_pending_location_create_failure, fixes a real defect
--    proven during the Phase 2.2A audit: create_location_with_xp inserts
--    with status='pending', but the general locations_delete RLS policy
--    only permits deleting rows with status IN ('draft','rejected'). If
--    LocationsRepository.createLocation's own rollback (a plain client
--    DELETE) ever ran after the RPC already succeeded but a later step
--    (the location_photos insert) failed, that DELETE would silently
--    match zero rows -- RLS-filtered deletes that match nothing do not
--    raise an error -- leaving a dangling 'pending' row with a
--    broken image_url (its Storage object gets removed by the existing,
--    unaffected client-side Storage cleanup, which has no status
--    restriction).
--
--    This RPC deletes a row ONLY if ALL of the following hold:
--      - the caller is authenticated (auth.uid() is not null)
--      - owner_id = auth.uid() (only your own location)
--      - request_id = the exact p_request_id the caller supplies (the
--        client-generated UUID unique to that one creation attempt --
--        this is what scopes cleanup to "the location THIS failed
--        request just created", not "any of my pending locations")
--      - status = 'pending' (never touches draft/approved/rejected rows
--        -- in particular it can NEVER be used to delete an
--        already-approved or already-rejected location, and it never
--        widens what the general locations_delete policy itself allows)
--    A call that matches nothing (row already gone, wrong owner, wrong
--    request_id, or status no longer 'pending') is a silent no-op --
--    idempotent, safe to retry, never raises just because there was
--    nothing to clean up.
--
--    This does not loosen locations_delete in any way; it is a separate,
--    additional, deliberately narrow capability that only ever reaches
--    the exact same subset of rows a client could already read/created
--    moments earlier in the same flow.

-- ---------------------------------------------------------------------------
-- 1. Widen create_location_with_xp (DROP + CREATE, not a second overload)
-- ---------------------------------------------------------------------------

drop function if exists public.create_location_with_xp(
  text, text, double precision, double precision, text, text, uuid
);

create function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude double precision,
  location_longitude double precision,
  p_image_url text,
  p_category text,
  p_request_id uuid,
  p_address text default null,
  p_amenities text[] default null,
  p_opening_hours jsonb default null,
  p_timezone text default null
)
returns uuid
language plpgsql security definer
set search_path = extensions, public, pg_catalog
as $function$
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
  if p_request_id is not null then
    select id into location_id from public.locations where owner_id=uid and request_id=p_request_id;
    if location_id is not null then return location_id; end if;
  end if;
  begin
    insert into public.locations(
      user_id,owner_id,title,name,description,coordinates,position,status,
      visibility,moderation,secrecy,category,image_url,request_id,
      address,amenities,opening_hours,timezone
    ) values (
      uid,uid,btrim(location_title),btrim(location_title),coalesce(btrim(location_description),''),
      st_setsrid(st_makepoint(location_longitude,location_latitude),4326)::geography,
      st_setsrid(st_makepoint(location_longitude,location_latitude),4326)::geography,
      'pending','public','pending','public',normalized_category,nullif(btrim(p_image_url),''),p_request_id,
      nullif(btrim(p_address),''),p_amenities,p_opening_hours,p_timezone
    ) returning id into location_id;
  exception when unique_violation then
    if p_request_id is null then raise; end if;
    select id into location_id from public.locations where owner_id=uid and request_id=p_request_id;
    if location_id is null then raise; end if;
  end;
  return location_id;
end
$function$;

revoke all on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text, uuid,
  text, text[], jsonb, text
) from public, anon;

grant execute on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text, uuid,
  text, text[], jsonb, text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Narrowly-scoped rollback-cleanup RPC for the CREATE flow only
-- ---------------------------------------------------------------------------

create function public.cleanup_own_pending_location_create_failure(
  p_location_id uuid,
  p_request_id uuid
)
returns void
language plpgsql security definer
set search_path = extensions, public, pg_catalog
as $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'authentication required'; end if;
  if p_location_id is null or p_request_id is null then
    raise exception 'location id and request id are required';
  end if;

  delete from public.locations
  where id = p_location_id
    and owner_id = uid
    and request_id = p_request_id
    and status = 'pending';
  -- Deliberately no "if not found" guard: a call that matches nothing
  -- (already cleaned up, already approved/rejected, wrong owner, wrong
  -- request_id) is a safe, idempotent no-op, not an error -- this is a
  -- best-effort rollback helper, not a user-facing delete action.
end
$function$;

revoke all on function public.cleanup_own_pending_location_create_failure(
  uuid, uuid
) from public, anon;

grant execute on function public.cleanup_own_pending_location_create_failure(
  uuid, uuid
) to authenticated, service_role;
