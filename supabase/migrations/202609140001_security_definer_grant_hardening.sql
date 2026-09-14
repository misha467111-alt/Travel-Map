-- SECURITY DEFINER GRANT HARDENING
--
-- Follow-up to the audit documented in supabase/BASELINE.md ("several
-- SECURITY DEFINER RPC functions grant execute to anon"). This migration
-- only changes EXECUTE grants/revokes on existing functions. It does not
-- redefine any function body, does not change RLS, and does not move any
-- privileged authority into the Flutter client.
--
-- Three independently-justified groups, each explained where it appears:
--   1. Close a real privilege-escalation hole (achievement_metric_value).
--   2. Revoke stale anon/public EXECUTE from trigger-only functions that
--      Postgres already refuses to invoke directly ("trigger functions
--      can only be called as triggers") -- zero behavior change, pure
--      attack-surface reduction.
--   3. Narrow four already-correctly-guarded client RPCs from anon to
--      authenticated-only, since every one of them already raises
--      'authentication required' when auth.uid() is null -- again zero
--      behavior change for real users, who are always 'authenticated'
--      once logged in.
--   4. One additive fix: grant a pure, side-effect-free validator
--      function the EXECUTE it will need the moment a currently-dormant
--      feature (opening_hours) is wired to a client write path.
--
-- service_role is never touched by this migration: it is not a
-- client-facing role, so narrowing it adds no security value.

-- ---------------------------------------------------------------------------
-- 1. Real finding: achievement_metric_value(uuid, text) is SECURITY
--    DEFINER, takes an arbitrary p_uid parameter with NO ownership check
--    in its body, and is directly EXECUTE-granted to both anon and
--    authenticated. As shipped, any client holding just the public anon
--    key (no login required) can call
--      achievement_metric_value('<any-other-users-uuid>', 'xp')
--    and read that user's exact XP, distance_traveled_km, friend count,
--    location count, check-in count, comment count, or photo count --
--    bypassing profile privacy entirely, since SECURITY DEFINER bypasses
--    RLS by design.
--
--    The function is never called directly by the Flutter client (grep
--    confirmed) and its only two legitimate callers,
--    check_and_unlock_achievements() and get_achievement_progress(), are
--    themselves SECURITY DEFINER and always pass their OWN auth.uid() --
--    never an externally supplied id. Because a SECURITY DEFINER
--    function's internal calls execute as the function owner, those two
--    callers do not need an explicit EXECUTE grant on
--    achievement_metric_value to keep working: revoking anon/authenticated
--    here only removes the direct, unscoped calling path.
-- ---------------------------------------------------------------------------
revoke execute on function public.achievement_metric_value(p_uid uuid, p_metric text)
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Trigger-only functions (RETURNS trigger). Postgres rejects a direct
--    call to a trigger function from any role ("trigger functions can
--    only be called as triggers"), and firing via CREATE TRIGGER does not
--    require the DML-issuing role to hold EXECUTE on the trigger function
--    at all -- both already proven safe in this codebase by
--    award_invite_for_level_unlock (confirmed unreachable directly in the
--    prior audit) and by comments_rating_aggregate_trigger /
--    recalculate_location_rating / travel_validate_location_filter_metadata,
--    which are already fully revoked from anon/authenticated/public in
--    earlier migrations with no reported regression. The anon/public/
--    authenticated grants below are therefore stale surface with zero
--    functional purpose; revoking them is a pure attack-surface reduction
--    with no behavior change for any real trigger firing.
--
--    handle_new_auth_user() and handle_new_user() are additionally
--    confirmed dead (defined but not attached to any trigger anywhere in
--    the migration chain) -- only handle_new_auth_user_compat() is live,
--    attached as on_auth_user_created on auth.users.
-- ---------------------------------------------------------------------------
revoke execute on function public.award_invite_for_level_unlock()
  from anon, authenticated;
revoke execute on function public.handle_new_auth_user()
  from anon, authenticated;
revoke execute on function public.handle_new_auth_user_compat()
  from public, anon, authenticated;
revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.notify_location_owner_about_comment()
  from public, anon, authenticated;
revoke execute on function public.notify_user_about_follow()
  from public, anon, authenticated;
revoke execute on function public.protect_location_system_fields()
  from anon, authenticated;
revoke execute on function public.set_comment_actor_compat()
  from public, anon, authenticated;
revoke execute on function public.set_follow_actor_compat()
  from public, anon, authenticated;
revoke execute on function public.set_photo_actor_compat()
  from public, anon, authenticated;
revoke execute on function public.set_profile_server_fields()
  from anon, authenticated;
revoke execute on function public.set_user_settings_updated_at()
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Four client RPCs that are correctly guarded internally (every one
--    raises 'authentication required' when auth.uid() is null) but are
--    still granted to anon. A real logged-in user is always the
--    'authenticated' role, never 'anon' -- the anon grant only lets an
--    unauthenticated caller reach the guard clause and get a rejection,
--    never do anything useful. Narrowing to authenticated-only removes
--    that pointless reachable surface without changing behavior for any
--    real user.
-- ---------------------------------------------------------------------------
revoke execute on function public.update_own_location(
  p_location_id uuid, p_title text, p_description text, p_category text
) from anon;
revoke execute on function public.create_check_in(
  target_location_id uuid, user_lat double precision, user_lng double precision,
  gps_accuracy_m double precision
) from anon;
revoke execute on function public.create_location_with_xp(
  text, text, double precision, double precision, text, text, uuid
) from anon;
revoke execute on function public.get_achievement_progress()
  from anon;

-- ---------------------------------------------------------------------------
-- 4. Additive, not a revoke: travel_opening_hours_is_valid(jsonb) is used
--    only inside locations_opening_hours_canonical_check, a CHECK
--    constraint on public.locations.opening_hours. A function referenced
--    in a CHECK constraint is evaluated with the privileges of the role
--    performing the INSERT/UPDATE, so authenticated needs EXECUTE on it
--    the moment any client write ever sets opening_hours to a non-null
--    value. No such write path exists in the Flutter app today (neither
--    create_location_with_xp nor update_own_location accepts an
--    opening_hours argument), so this is currently unreachable and
--    therefore not an active bug -- but the function's EXECUTE was fully
--    revoked (from every role, including authenticated) in
--    202608290002_reference_filters_rpc_acl.sql, which means the first
--    write path that ever sets opening_hours will fail with a permission
--    error at the constraint, not a validation error, unless this is
--    granted first. The function is IMMUTABLE and STRICT, takes only a
--    jsonb value, and touches no table -- granting it EXECUTE carries no
--    privilege-escalation risk of any kind. Fixing this now, ahead of the
--    feature that will need it, avoids a confusing failure mode later.
-- ---------------------------------------------------------------------------
grant execute on function public.travel_opening_hours_is_valid(jsonb)
  to authenticated;
