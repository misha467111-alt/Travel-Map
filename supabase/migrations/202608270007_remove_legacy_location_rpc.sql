-- Remove the obsolete five-argument overload. The canonical RPC includes p_category.
drop function if exists public.create_location_with_xp(
  text,
  text,
  double precision,
  double precision,
  text
);
