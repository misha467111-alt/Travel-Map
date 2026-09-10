alter table public.locations
  add column if not exists address text,
  add column if not exists amenities text[];

alter table public.locations
  drop constraint if exists locations_amenities_canonical_check;

alter table public.locations
  add constraint locations_amenities_canonical_check
  check (
    amenities is null
    or (
      array_position(amenities, null) is null
      and amenities <@ array[
        'parking', 'wifi', 'toilet',
        'accessibility', 'pets', 'food'
      ]::text[]
    )
  );
