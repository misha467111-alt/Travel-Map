-- FIX PHASE 1 — SECURITY + DATABASE
--
-- 1. Harden places_photos storage write policies to owner-scoped access,
--    mirroring the pattern already used by avatars/location_images.
--    SELECT (read) policy is left untouched — this only replaces the
--    ungoverned write policies.
-- 2. Add the missing index on location_photos.location_id.
-- 3. Revoke unnecessary anon write grants on friendships/reviews/
--    achievement_definitions (RLS already blocks these; this removes the
--    redundant second attack-surface layer). SELECT and all `authenticated`
--    grants are left untouched.

-- ---------------------------------------------------------------------------
-- 1. places_photos: owner-scoped write policies
-- ---------------------------------------------------------------------------
drop policy if exists "All Access 31i9xw_1" on storage.objects; -- old UPDATE (no ownership scope)
drop policy if exists "All Access 31i9xw_2" on storage.objects; -- old DELETE (no ownership scope)
drop policy if exists "All Access 31i9xw_3" on storage.objects; -- old INSERT (no ownership scope)

drop policy if exists "places_photos_owner_insert" on storage.objects;
drop policy if exists "places_photos_owner_update" on storage.objects;
drop policy if exists "places_photos_owner_delete" on storage.objects;

create policy "places_photos_owner_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'places_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "places_photos_owner_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'places_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'places_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "places_photos_owner_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'places_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 2. Missing FK-supporting index
-- ---------------------------------------------------------------------------
create index if not exists location_photos_location_id_idx
  on public.location_photos (location_id);

-- ---------------------------------------------------------------------------
-- 3. Redundant anon write grants
-- ---------------------------------------------------------------------------
revoke insert, update, delete on public.friendships from anon;
revoke insert, update, delete on public.reviews from anon;
revoke insert, update, delete on public.achievement_definitions from anon;
