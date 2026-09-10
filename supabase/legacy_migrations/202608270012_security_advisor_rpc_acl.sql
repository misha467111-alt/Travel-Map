-- Security-only ACL hardening. No table data, function bodies, RLS policies,
-- XP, auth, invite accounting, or PostGIS extension objects are changed.

-- Canonical invite operations are trusted SECURITY DEFINER RPCs. They must
-- never be callable by anonymous/PUBLIC roles.
revoke execute on function public.create_invite() from public, anon;
revoke execute on function public.redeem_invite(text) from public, anon;
grant execute on function public.create_invite() to authenticated, service_role;
grant execute on function public.redeem_invite(text) to authenticated, service_role;

-- spatial_ref_sys is extension-managed by supabase_admin. Its Data API
-- exposure is retained and classified as a system-table finding; unsafe
-- ACL/RLS changes are intentionally not attempted.
