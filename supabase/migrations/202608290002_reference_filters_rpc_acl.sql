-- Correct only the explicit client ACL inherited by the v2 functions from
-- production default privileges. Function ownership and bodies are unchanged.

revoke execute on function public.travel_locations_in_bounds_v2(
  double precision, double precision, double precision, double precision,
  text, text, double precision, double precision, double precision, numeric,
  boolean, boolean, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.travel_locations_in_bounds_v2(
  double precision, double precision, double precision, double precision,
  text, text, double precision, double precision, double precision, numeric,
  boolean, boolean, text, integer
) to authenticated;

revoke execute on function public.travel_location_is_open_now(
  jsonb, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.travel_location_is_open_now(
  jsonb, text, timestamptz
) to authenticated;

revoke execute on function public.travel_opening_hours_is_valid(jsonb)
  from public, anon, authenticated, service_role;

revoke execute on function public.travel_validate_location_filter_metadata()
  from public, anon, authenticated, service_role;
