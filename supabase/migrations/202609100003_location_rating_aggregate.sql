-- FIX PHASE 3 — LOCATION RATING AGGREGATE
--
-- public.locations.rating / ratings_count are protected system fields
-- (forced to 0 on insert, and any client UPDATE is rejected by
-- protect_location_system_fields). No mechanism has ever existed to keep
-- them in sync with public.comments.rating, so both are permanently 0 for
-- every location today, making the app's "minimum rating" filter and
-- "sort by rating" feature silently non-functional.
--
-- This migration adds a trusted, server-side aggregate:
--   ratings_count = count of comments for the location with a non-null
--                   rating and status = 'visible'
--   rating        = average of those ratings, rounded to 2 decimals
--   (both are 0 when there are no qualifying comments)
--
-- maintained automatically after INSERT/UPDATE/DELETE on public.comments,
-- plus a one-time deterministic backfill from existing data.
--
-- No RLS change. No client grant change. No column added. Client
-- permissions are not weakened: authenticated users still cannot UPDATE
-- locations.rating/ratings_count directly — only this new SECURITY
-- DEFINER path (invoked solely by the comments trigger, never callable
-- by anon/authenticated) can set them, following the exact same trusted
-- pattern already used by record_location_moderation_result /
-- try_claim_location_moderation.

-- ---------------------------------------------------------------------------
-- 1. Aggregate recompute helper.
--    SECURITY DEFINER (owned by postgres, matching the existing trusted
--    functions) so that, when it runs, current_user is 'postgres' rather
--    than 'authenticated' — this is what lets its UPDATE on
--    public.locations pass through protect_location_system_fields'
--    "authenticated cannot change system fields" guard without weakening
--    that guard for any client-initiated write.
--
--    The target row is locked first (SELECT ... FOR UPDATE) before the
--    aggregate is computed, so concurrent recalculations for the same
--    location serialize instead of racing: each one's SELECT only runs
--    once it holds the lock, so it always sees every already-committed
--    sibling change. If the location no longer exists (e.g. it was
--    deleted and this fired from a cascade-deleted comment), both the
--    lock attempt and the final UPDATE simply affect zero rows — no
--    error.
-- ---------------------------------------------------------------------------
create or replace function public.recalculate_location_rating(p_location_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_count integer;
  v_avg numeric;
begin
  if p_location_id is null then
    return;
  end if;

  perform 1 from public.locations where id = p_location_id for update;

  select count(*), avg(rating)
    into v_count, v_avg
    from public.comments
    where location_id = p_location_id
      and rating is not null
      and status = 'visible'::social_content_status;

  update public.locations
     set rating = coalesce(round(v_avg, 2), 0),
         ratings_count = coalesce(v_count, 0)
   where id = p_location_id;
end;
$$;

revoke execute on function public.recalculate_location_rating(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Trigger function on public.comments. Recomputes the affected
--    location(s): the new location_id always, and the old location_id
--    too if a comment's location_id was actually changed on UPDATE (RLS
--    currently allows an author to update their own comment's
--    location_id, so this is handled even though the app is not known to
--    exercise it).
-- ---------------------------------------------------------------------------
create or replace function public.comments_rating_aggregate_trigger()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
begin
  if tg_op = 'INSERT' then
    perform public.recalculate_location_rating(new.location_id);
    return new;
  elsif tg_op = 'UPDATE' then
    perform public.recalculate_location_rating(new.location_id);
    if new.location_id is distinct from old.location_id then
      perform public.recalculate_location_rating(old.location_id);
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    perform public.recalculate_location_rating(old.location_id);
    return old;
  end if;
  return null;
end;
$$;

revoke execute on function public.comments_rating_aggregate_trigger() from public, anon, authenticated;

drop trigger if exists comments_rating_aggregate on public.comments;

-- UPDATE OF rating, status, location_id: only these column changes can
-- change the aggregate, so unrelated updates (text/body/updated_at/...)
-- do not fire a recompute. INSERT and DELETE always fire.
create trigger comments_rating_aggregate
  after insert or update of rating, status, location_id or delete
  on public.comments
  for each row
  execute function public.comments_rating_aggregate_trigger();

-- ---------------------------------------------------------------------------
-- 3. One-time deterministic backfill from current data. Runs as the
--    migration role (postgres), so it is likewise unaffected by
--    protect_location_system_fields' authenticated-only guard. Safe to
--    re-run: it always recomputes to the same correct values.
-- ---------------------------------------------------------------------------
with agg as (
  select location_id,
         count(*) as cnt,
         round(avg(rating)::numeric, 2) as avg_rating
  from public.comments
  where rating is not null
    and status = 'visible'::social_content_status
  group by location_id
)
update public.locations l
   set rating = coalesce(agg.avg_rating, 0),
       ratings_count = coalesce(agg.cnt, 0)
  from agg
 where agg.location_id = l.id;

update public.locations l
   set rating = 0,
       ratings_count = 0
 where not exists (
   select 1 from public.comments c
   where c.location_id = l.id
     and c.rating is not null
     and c.status = 'visible'::social_content_status
 )
 and (l.rating is distinct from 0 or l.ratings_count is distinct from 0);
