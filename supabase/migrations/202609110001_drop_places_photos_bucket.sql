-- PLACES_PHOTOS CLEANUP
--
-- public.places_photos (storage bucket) is confirmed orphaned:
--   - not referenced anywhere in the Flutter app (lib/)
--   - not referenced in any Edge Function
--   - not referenced by any SQL function or trigger
--   - storage.objects count for this bucket = 0 (re-verified immediately
--     before this migration was applied)
--   - its write policies were already hardened to an owner-scoped pattern
--     in 202609100001_fix_phase1_security_database.sql
--
-- This migration removes the now-unnecessary bucket entirely: its storage
-- policies, any (zero) objects, and the bucket row itself. Does not touch
-- avatars, location_images, or any other bucket/policy/grant.

drop policy if exists "All Access 31i9xw_0" on storage.objects;
drop policy if exists "places_photos_owner_insert" on storage.objects;
drop policy if exists "places_photos_owner_update" on storage.objects;
drop policy if exists "places_photos_owner_delete" on storage.objects;

-- storage.objects/storage.buckets carry a platform-level protect_delete()
-- guard that rejects any direct SQL DELETE unless this session setting is
-- explicitly enabled. This is the officially supported escape hatch for
-- trusted migration contexts (distinct from any client-facing RLS/grant),
-- scoped to this transaction only via SET LOCAL.
set local storage.allow_delete_query = 'true';

delete from storage.objects where bucket_id = 'places_photos';

delete from storage.buckets where id = 'places_photos';
