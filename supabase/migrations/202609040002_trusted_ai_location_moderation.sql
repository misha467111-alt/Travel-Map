-- Trusted moderation and approval-time reward. Review only; do not auto-apply.
alter table public.locations add column if not exists approval_rewarded_at timestamptz;
alter table public.locations add column if not exists moderation_started_at timestamptz;

create table if not exists public.location_moderation_audits (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id) on delete cascade,
  decision text,
  confidence numeric(5,4),
  reason_codes text[] not null default '{}',
  short_reason text,
  provider text not null,
  model text not null,
  attempt_status text not null,
  error_code text,
  created_at timestamptz not null default now(),
  constraint location_moderation_audits_decision_check check (decision is null or decision in ('approve','review','reject')),
  constraint location_moderation_audits_confidence_check check (confidence is null or confidence between 0 and 1),
  constraint location_moderation_audits_attempt_status_check check (attempt_status in ('succeeded','error')),
  constraint location_moderation_audits_provider_check check (btrim(provider) <> ''),
  constraint location_moderation_audits_model_check check (btrim(model) <> ''),
  constraint location_moderation_audits_reason_codes_check check (cardinality(reason_codes) <= 20 and array_position(reason_codes, null) is null),
  constraint location_moderation_audits_result_shape_check check (
    (attempt_status='succeeded' and decision is not null and confidence is not null and error_code is null)
    or
    (attempt_status='error' and decision is null and confidence is null and nullif(btrim(error_code),'') is not null)
  )
);

create index if not exists location_moderation_audits_location_created_idx
  on public.location_moderation_audits(location_id, created_at desc);
alter table public.location_moderation_audits enable row level security;
revoke all on table public.location_moderation_audits from public, anon, authenticated;
grant select, insert on table public.location_moderation_audits to service_role;

create or replace function public.try_claim_location_moderation(p_location_id uuid)
returns boolean
language plpgsql security definer
set search_path = public, pg_catalog
as $function$
begin
  update public.locations
  set moderation_started_at=now()
  where id=p_location_id
    and status='pending'
    and (
      moderation_started_at is null
      or moderation_started_at < now() - interval '2 minutes'
    );
  return found;
end
$function$;

revoke all on function public.try_claim_location_moderation(uuid)
  from public, anon, authenticated;
grant execute on function public.try_claim_location_moderation(uuid)
  to service_role;

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
      update public.profiles set xp=coalesce(xp,0)+10 where id=location_owner;
    end if;
  elsif next_status <> current_status then
    update public.locations set status=next_status, moderation_started_at=null where id=p_location_id;
  else
    update public.locations set moderation_started_at=null where id=p_location_id;
  end if;
  return next_status;
end
$function$;

revoke all on function public.record_location_moderation_result(uuid,text,double precision,text[],text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.record_location_moderation_result(uuid,text,double precision,text[],text,text,text,text,text)
  to service_role;

-- Signature remains compatible with Flutter. Pending submissions earn no XP.
create or replace function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude double precision,
  location_longitude double precision,
  p_image_url text,
  p_category text,
  p_request_id uuid
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
      visibility,moderation,secrecy,category,image_url,request_id
    ) values (
      uid,uid,btrim(location_title),btrim(location_title),coalesce(btrim(location_description),''),
      st_setsrid(st_makepoint(location_longitude,location_latitude),4326)::geography,
      st_setsrid(st_makepoint(location_longitude,location_latitude),4326)::geography,
      'pending','public','pending','public',normalized_category,nullif(btrim(p_image_url),''),p_request_id
    ) returning id into location_id;
  exception when unique_violation then
    if p_request_id is null then raise; end if;
    select id into location_id from public.locations where owner_id=uid and request_id=p_request_id;
    if location_id is null then raise; end if;
  end;
  return location_id;
end
$function$;

revoke all on function public.create_location_with_xp(text,text,double precision,double precision,text,text,uuid)
  from public, anon;
grant execute on function public.create_location_with_xp(text,text,double precision,double precision,text,text,uuid)
  to authenticated, service_role;

-- Disable the legacy six-argument entrypoint: its live implementation awards
-- XP at submission time and would bypass the approval-time reward invariant.
revoke all on function public.create_location_with_xp(text,text,double precision,double precision,text,text)
  from public, anon, authenticated;
grant execute on function public.create_location_with_xp(text,text,double precision,double precision,text,text)
  to service_role;
