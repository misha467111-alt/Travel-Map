-- PHASE 2B -- ACTIVITY EVENTS FOUNDATION
--
-- NOT APPLIED. Written and reviewed only, per explicit instruction
-- (Product Foundation Phase 2B). Implements the approved
-- "TRAVEL MAP -- ACTIVITY EVENTS DATA CONTRACT v1" design.
--
-- Goal: a single authoritative, append-only record of verified real-world
-- activity (activity_events), a server-controlled reward table
-- (activity_reward_rules) deciding which event types are XP-eligible and
-- by how much, and one internal helper (_record_activity_event) that every
-- feature RPC calls from inside its own transaction. The client can never
-- reach any of this with a direct INSERT/UPDATE/DELETE -- only through
-- feature RPCs it already calls today (create_check_in,
-- record_location_moderation_result), whose EXTERNAL behavior is
-- unchanged: same signatures (create_check_in gains one new OPTIONAL
-- trailing parameter, exactly like create_location_with_xp's own
-- request_id widening in 202609160001), same response shapes, same XP
-- amounts (+20 check-in, +10 approval), same 5-level/invite-unlock
-- trigger chain (profile_level_for_xp / travel_level_tier /
-- set_profile_server_fields / award_invite_for_level_unlock), all
-- completely untouched by this migration.
--
-- Zero regression / zero replay: no historical activity_events rows are
-- backfilled, no existing profiles.xp/level/invite_balance/
-- highest_level_rewarded value is read or written by this migration
-- itself -- only NEW check-ins and NEW approvals, from the moment this is
-- applied, ever create an activity_events row.

-- ---------------------------------------------------------------------------
-- 1. activity_event_types -- the closed, extensible taxonomy.
--
--    A lookup table, not a native Postgres ENUM: new event types (Quest,
--    Treasure, GPS routes) can be reserved with a plain INSERT rather than
--    an ALTER TYPE, and activity_events.event_type can be a normal FK
--    instead of needing type-widening machinery later.
-- ---------------------------------------------------------------------------

create table public.activity_event_types (
  key text primary key,
  description text not null
);

insert into public.activity_event_types (key, description) values
  ('LOCATION_APPROVED', 'A submitted location passed moderation and became publicly visible for the first time.'),
  ('LOCATION_VISITED', 'An authenticated user completed a GPS-verified check-in at a location.'),
  ('LOCATION_CREATED', 'A user submitted a new location for moderation. Reserved: not yet written by any RPC in this migration.'),
  ('ROUTE_PLANNED_CREATED', 'A user saved a planned (waypoint) route. Reserved for a future phase.'),
  ('ROUTE_RECORDED_COMPLETED', 'A user finished recording their own GPS route. Reserved: GPS sync is not implemented yet.'),
  ('ROUTE_FOLLOWED_COMPLETED', 'A user completed someone else''s reference recorded route. Reserved: schema not yet designed (creator track vs participant track).'),
  ('QUEST_COMPLETED', 'A user completed a quest. Reserved: quest schema does not exist yet.'),
  ('TREASURE_FOUND', 'A user found a treasure. Reserved: treasure schema does not exist yet.');

alter table public.activity_event_types enable row level security;

create policy activity_event_types_read on public.activity_event_types
  as permissive for select to authenticated using (true);

revoke all on table public.activity_event_types from public, anon, authenticated;
grant select on table public.activity_event_types to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. activity_reward_rules -- server-controlled, never client-writable.
--
--    Stores WHETHER and HOW MUCH XP an event type is worth, as data
--    instead of scattered PL/pgSQL literals, so a future event type only
--    ever needs a new row here plus a call to the shared helper -- never
--    new reward logic. `is_active=false` is an explicit extra gate (not
--    just `xp_amount=0`) so a reserved event type can exist in the
--    taxonomy without being reward-eligible the moment anything first
--    writes it, even by future accident.
-- ---------------------------------------------------------------------------

create table public.activity_reward_rules (
  event_type text primary key references public.activity_event_types(key),
  xp_amount integer not null default 0,
  is_active boolean not null default false,
  updated_at timestamp with time zone not null default now(),
  constraint activity_reward_rules_xp_amount_nonneg_check check (xp_amount >= 0)
);

insert into public.activity_reward_rules (event_type, xp_amount, is_active) values
  ('LOCATION_APPROVED', 10, true),
  ('LOCATION_VISITED', 20, true),
  ('LOCATION_CREATED', 0, false),
  ('ROUTE_PLANNED_CREATED', 0, false),
  ('ROUTE_RECORDED_COMPLETED', 0, false),
  ('ROUTE_FOLLOWED_COMPLETED', 0, false),
  ('QUEST_COMPLETED', 0, false),
  ('TREASURE_FOUND', 0, false);

alter table public.activity_reward_rules enable row level security;

create policy activity_reward_rules_read on public.activity_reward_rules
  as permissive for select to authenticated using (true);

revoke all on table public.activity_reward_rules from public, anon, authenticated;
grant select on table public.activity_reward_rules to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. activity_events -- the authoritative, append-only activity log.
--
--    subject_id answers "what is this event about" (for history/UI --
--    always the canonical domain entity, e.g. locations.id). source_id
--    answers "which exact fact instance caused this" and is the
--    idempotency anchor: for a one-time-ever fact (LOCATION_APPROVED)
--    subject_id and source_id are the same row; for a repeatable fact
--    (LOCATION_VISITED) they differ (subject_id=locations.id,
--    source_id=check_ins.id), so a user can visit the same location many
--    times while each individual check-in still gets exactly one event.
--
--    No geography, no duplicated entity content: metadata is for small
--    scalar display hints only. Display data is always joined from the
--    canonical table via subject_type/subject_id, never copied here.
-- ---------------------------------------------------------------------------

create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null references public.activity_event_types(key),
  subject_type text not null,
  subject_id uuid not null,
  source_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  xp_awarded integer not null default 0,
  occurred_at timestamp with time zone not null,
  created_at timestamp with time zone not null default now(),
  constraint activity_events_subject_type_not_blank_check check (btrim(subject_type) <> ''),
  constraint activity_events_xp_awarded_nonneg_check check (xp_awarded >= 0)
);

-- The universal idempotency backstop: no code path, however many times it
-- is retried, can ever cause two rows for the same (user, event type,
-- exact fact instance) -- and since the reward is only ever applied
-- immediately after a row is confirmed newly inserted (see
-- _record_activity_event below), this is also the backstop against
-- duplicate XP, independent of whatever domain-level guard a given
-- feature RPC also happens to have.
create unique index activity_events_user_type_source_uidx
  on public.activity_events (user_id, event_type, source_id);

-- Primary UI access pattern: a user's own chronological history, newest
-- first. Doubles as the natural index for "has this user done event type
-- X at all" scans (achievement evaluation for future event-log-backed
-- metrics) since user_id is the leading column.
create index activity_events_user_occurred_idx
  on public.activity_events (user_id, occurred_at desc);

alter table public.activity_events enable row level security;

create policy activity_events_read_own on public.activity_events
  as permissive for select to authenticated
  using (user_id = (select auth.uid()));

-- No INSERT/UPDATE/DELETE policy for any client-facing role is defined
-- above, deliberately: the guarantee that a client cannot fabricate an
-- event does not rest on RLS `with check` logic getting it right -- it
-- rests on `authenticated`/`anon` never holding the underlying table
-- privilege at all (see the grants below), which is a strictly simpler
-- and harder-to-get-wrong guarantee. Matches this project's existing
-- append-only-audit-table precedent exactly
-- (public.location_moderation_audits, 202609040002): revoke all from
-- public/anon/authenticated, grant only SELECT+INSERT to service_role,
-- no UPDATE/DELETE grant to anyone ever.
revoke all on table public.activity_events from public, anon, authenticated;
grant select on table public.activity_events to authenticated;
grant select, insert on table public.activity_events to service_role;

-- ---------------------------------------------------------------------------
-- 4. _record_activity_event -- the one sanctioned write path.
--
--    SECURITY DEFINER, controlled search_path. This is internal plumbing,
--    not a public RPC: it is only ever called from inside another
--    SECURITY DEFINER function's own body (create_check_in,
--    record_location_moderation_result, and future feature RPCs), which
--    executes as the function owner regardless of the calling role's own
--    grants -- so the leading-underscore name and the revokes below are
--    the only things stopping a client from invoking it directly via
--    PostgREST, not a functional requirement for feature RPCs to keep
--    working.
--
--    The reward lookup happens BEFORE the insert (not as a follow-up
--    UPDATE): the realized xp_awarded is computed once and written
--    directly in the same INSERT that creates the row, so the table never
--    needs an UPDATE grant for anyone, including this function's own
--    owner acting through it -- append-only is enforced by construction,
--    not by convention. If the insert is skipped by
--    ON CONFLICT DO NOTHING (this exact event already exists), the
--    reward is never applied and the caller is told 0/none, full stop.
-- ---------------------------------------------------------------------------

create function public._record_activity_event(
  p_user_id uuid,
  p_event_type text,
  p_subject_type text,
  p_subject_id uuid,
  p_source_id uuid,
  p_metadata jsonb default '{}'::jsonb,
  p_occurred_at timestamp with time zone default now()
)
returns table(event_id uuid, xp_awarded integer)
language plpgsql
security definer
set search_path = extensions, public, pg_catalog
as $function$
declare
  reward_amount integer;
  reward_active boolean;
  realized_xp integer := 0;
  inserted_id uuid;
begin
  if p_user_id is null then raise exception 'user_id is required'; end if;
  if p_event_type is null then raise exception 'event_type is required'; end if;
  if p_subject_type is null or btrim(p_subject_type) = '' then
    raise exception 'subject_type is required';
  end if;
  if p_subject_id is null then raise exception 'subject_id is required'; end if;
  if p_source_id is null then raise exception 'source_id is required'; end if;

  select r.xp_amount, r.is_active into reward_amount, reward_active
  from public.activity_reward_rules r
  where r.event_type = p_event_type;

  if coalesce(reward_active, false) then
    realized_xp := coalesce(reward_amount, 0);
  end if;

  insert into public.activity_events(
    user_id, event_type, subject_type, subject_id, source_id,
    metadata, xp_awarded, occurred_at
  ) values (
    p_user_id, p_event_type, p_subject_type, p_subject_id, p_source_id,
    coalesce(p_metadata, '{}'::jsonb), realized_xp, coalesce(p_occurred_at, now())
  )
  on conflict (user_id, event_type, source_id) do nothing
  returning id into inserted_id;

  if inserted_id is null then
    -- Already recorded (duplicate/retry of the exact same fact instance).
    -- Never award XP twice, never re-derive a reward for an event that
    -- already happened.
    return query select null::uuid, 0;
    return;
  end if;

  if realized_xp > 0 then
    update public.profiles set xp = coalesce(xp, 0) + realized_xp where id = p_user_id;
  end if;

  return query select inserted_id, realized_xp;
end
$function$
;

revoke all on function public._record_activity_event(
  uuid, text, text, uuid, uuid, jsonb, timestamp with time zone
) from public, anon, authenticated;

-- service_role is intentionally left granted, matching this project's
-- established convention (202609140001_security_definer_grant_hardening.sql:
-- "service_role is never touched by this migration: it is not a
-- client-facing role, so narrowing it adds no security value"). This is
-- not a sanctioned direct-call path for normal operation -- feature RPCs
-- reach this function as the table owner regardless -- it simply keeps
-- the door open for legitimate backend/ops tooling without a future
-- migration, exactly like every other SECURITY DEFINER function here.
grant execute on function public._record_activity_event(
  uuid, text, text, uuid, uuid, jsonb, timestamp with time zone
) to service_role;

-- ---------------------------------------------------------------------------
-- 5. create_check_in -- widened with one optional trailing p_request_id,
--    and internally refactored to call the shared helper.
--
--    DROP + CREATE (not a second overload), for the exact reason already
--    established and tested for create_location_with_xp in
--    202609160001: the current live Flutter caller
--    (SupabaseCheckInRepository.checkIn) invokes this RPC with PostgREST's
--    named-argument convention using only the original 4 parameter names.
--    A second, parallel 5-argument overload would be an equally valid
--    match for that same call (its 5th parameter has a default), and
--    Postgres would refuse the call as "not unique". Replacing the single
--    4-argument function in place with a 5-argument one (1 new trailing
--    optional parameter, defaulting to null) leaves exactly one function
--    matching that call shape, so EVERY existing caller -- including any
--    that never gets updated to send p_request_id -- keeps working
--    unchanged, with request_id-based idempotency simply not applying to
--    it (identical to how create_location_with_xp's pre-existing 7-name
--    callers still work after that migration).
--
--    External behavior for a caller that supplies p_request_id: an EXACT
--    retry (same user, same request_id) returns the ORIGINAL
--    {check_in_id, xp_awarded} instead of creating a second check-in,
--    raising the cooldown error, or awarding XP again. A caller that
--    changes location/coordinates/etc. but reuses an old request_id is
--    out of scope for this guarantee -- request_id identifies "the same
--    attempt", not "any check-in by this user ever". A genuinely NEW
--    check-in (a different, or omitted, request_id) is governed only by
--    the pre-existing 30-minute cooldown, exactly as before -- idempotency
--    and rate limiting remain two separate, non-overlapping mechanisms.
-- ---------------------------------------------------------------------------

alter table public.check_ins add column if not exists request_id uuid;

create unique index if not exists check_ins_user_request_id_uidx
  on public.check_ins using btree (user_id, request_id)
  where (request_id is not null);

drop function if exists public.create_check_in(
  uuid, double precision, double precision, double precision
);

create function public.create_check_in(
  target_location_id uuid,
  user_lat double precision,
  user_lng double precision,
  gps_accuracy_m double precision,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = extensions, public, pg_catalog
as $function$
declare
  uid uuid := auth.uid();
  target geography;
  check_in_id uuid;
  awarded integer := 0;
  recent_count integer;
  existing_check_in_id uuid;
  event_row record;
begin
  if uid is null then raise exception 'authentication required'; end if;
  if user_lat not between -90 and 90 or user_lng not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  if gps_accuracy_m is null or gps_accuracy_m < 0 or gps_accuracy_m > 100 then
    raise exception 'GPS accuracy is insufficient';
  end if;

  if p_request_id is not null then
    select id into existing_check_in_id
    from public.check_ins
    where user_id = uid and request_id = p_request_id;
    if existing_check_in_id is not null then
      select coalesce(xp_awarded, 0) into awarded
      from public.activity_events
      where user_id = uid and event_type = 'LOCATION_VISITED' and source_id = existing_check_in_id;
      return jsonb_build_object('check_in_id', existing_check_in_id, 'xp_awarded', coalesce(awarded, 0));
    end if;
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

  begin
    insert into public.check_ins(user_id,location_id,position,accuracy_m,request_id)
    values(
      uid,
      target_location_id,
      st_setsrid(st_makepoint(user_lng,user_lat),4326)::geography,
      gps_accuracy_m,
      p_request_id
    )
    returning id into check_in_id;
  exception when unique_violation then
    if p_request_id is null then raise; end if;
    select id into check_in_id from public.check_ins where user_id=uid and request_id=p_request_id;
    if check_in_id is null then raise; end if;
    select coalesce(xp_awarded, 0) into awarded
    from public.activity_events
    where user_id=uid and event_type='LOCATION_VISITED' and source_id=check_in_id;
    return jsonb_build_object('check_in_id', check_in_id, 'xp_awarded', coalesce(awarded, 0));
  end;

  select * into event_row from public._record_activity_event(
    p_user_id := uid,
    p_event_type := 'LOCATION_VISITED',
    p_subject_type := 'location',
    p_subject_id := target_location_id,
    p_source_id := check_in_id,
    p_metadata := '{}'::jsonb,
    p_occurred_at := now()
  );
  awarded := coalesce(event_row.xp_awarded, 0);

  return jsonb_build_object('check_in_id',check_in_id,'xp_awarded',awarded);
end
$function$
;

revoke all on function public.create_check_in(
  uuid, double precision, double precision, double precision, uuid
) from public, anon;

grant execute on function public.create_check_in(
  uuid, double precision, double precision, double precision, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. record_location_moderation_result -- internal refactor only.
--
--    Signature, return type, validation, audit insert, and the
--    approval_rewarded_at guard are ALL preserved byte-for-byte. The one
--    change: the inline `update public.profiles set xp=coalesce(xp,0)+10`
--    is replaced with a call to the shared helper. approval_rewarded_at
--    remains the domain-level guard (a location can only ever transition
--    into 'approved' once); activity_events' own uniqueness on
--    (user_id, event_type, source_id) -- source_id=p_location_id, which
--    is itself unique forever -- is the additional, independent backstop,
--    exactly per the approved contract's "defense in depth" principle.
--    A retry after a successful approval still raises
--    'location is not pending moderation' exactly as before (unchanged),
--    so this can never produce duplicate XP either way.
-- ---------------------------------------------------------------------------

create or replace function public.record_location_moderation_result(
  p_location_id uuid,
  p_decision text,
  p_confidence double precision,
  p_reason_codes text[],
  p_short_reason text,
  p_provider text,
  p_model text,
  p_attempt_status text,
  p_error_code text default null
)
returns public.location_status
language plpgsql security definer
set search_path = public, pg_catalog
as $function$
declare
  current_status public.location_status;
  location_owner uuid;
  reward_already_given boolean;
  next_status public.location_status;
  normalized_provider text := nullif(btrim(p_provider),'');
  normalized_model text := nullif(btrim(p_model),'');
  normalized_error text := nullif(btrim(p_error_code),'');
begin
  if normalized_provider is null or normalized_model is null then
    raise exception 'provider and model are required' using errcode='22023';
  end if;
  if p_attempt_status not in ('succeeded','error') then
    raise exception 'invalid moderation attempt status' using errcode='22023';
  end if;
  if coalesce(cardinality(p_reason_codes),0) > 20 or array_position(p_reason_codes,null) is not null then
    raise exception 'invalid moderation reason codes' using errcode='22023';
  end if;
  if p_attempt_status='succeeded' and (
    p_decision not in ('approve','review','reject') or p_confidence is null
    or p_confidence < 0 or p_confidence > 1 or normalized_error is not null
  ) then raise exception 'invalid successful moderation result' using errcode='22023'; end if;
  if p_attempt_status='error' and (
    p_decision is not null or p_confidence is not null or normalized_error is null
  ) then raise exception 'invalid moderation error result' using errcode='22023'; end if;

  select status, owner_id, approval_rewarded_at is not null
    into current_status, location_owner, reward_already_given
  from public.locations where id=p_location_id for update;
  if not found then raise exception 'location not found' using errcode='P0002'; end if;
  if current_status <> 'pending' then
    raise exception 'location is not pending moderation' using errcode='55000';
  end if;

  insert into public.location_moderation_audits(
    location_id,decision,confidence,reason_codes,short_reason,provider,model,attempt_status,error_code
  ) values (
    p_location_id,p_decision,p_confidence,coalesce(p_reason_codes,'{}'),
    nullif(left(btrim(coalesce(p_short_reason,'')),280),''),normalized_provider,
    normalized_model,p_attempt_status,normalized_error
  );

  next_status := case
    when p_attempt_status='error' then 'pending'::public.location_status
    when p_decision='approve' then 'approved'::public.location_status
    when p_decision='reject' then 'rejected'::public.location_status
    else 'pending'::public.location_status
  end;

  if next_status='approved' and not reward_already_given then
    update public.locations set status='approved', approval_rewarded_at=now(), moderation_started_at=null
    where id=p_location_id and approval_rewarded_at is null;
    if found then
      perform public._record_activity_event(
        p_user_id := location_owner,
        p_event_type := 'LOCATION_APPROVED',
        p_subject_type := 'location',
        p_subject_id := p_location_id,
        p_source_id := p_location_id,
        p_metadata := '{}'::jsonb,
        p_occurred_at := now()
      );
    end if;
  elsif next_status <> current_status then
    update public.locations set status=next_status, moderation_started_at=null where id=p_location_id;
  else
    update public.locations set moderation_started_at=null where id=p_location_id;
  end if;
  return next_status;
end
$function$;

-- Grants unchanged from 202609040002 -- create or replace preserves the
-- existing grants of an unchanged signature, so these are restated only
-- for clarity/auditability, not because anything actually changes here.
revoke all on function public.record_location_moderation_result(uuid,text,double precision,text[],text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.record_location_moderation_result(uuid,text,double precision,text[],text,text,text,text,text)
  to service_role;
