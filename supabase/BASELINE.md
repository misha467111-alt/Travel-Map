# Canonical production baseline

- Baseline version: `202608290000`
- Baseline migration: `202608290000_production_canonical_baseline.sql`
- Factual source: linked production PostgreSQL catalog snapshot obtained with read-only Supabase CLI catalog queries
- Snapshot date: 2026-08-30 (Europe/Kyiv)
- Next feature migration: `202608290001_reference_filters_v2.sql`

## Why the historical chain is archived

The former 26-file local migration chain is not the cumulative history of the linked production database. Remote migration history is empty, `202608250001_initial_travel_schema.sql` describes objects absent from production, and two files share version `202608250002`. Applying or blindly repairing that chain would misrepresent production and could replay obsolete SQL.

The files are retained unchanged in `supabase/legacy_migrations/` as historical evidence. They are not part of the active deployment chain.

Duplicate historical version:

- `202608250002_profile_gamification.sql`
- `202608250002_storage_realtime.sql`

## Canonical scope

The baseline describes the factual project-owned production schema: extensions needed for bootstrap, three project enums, 21 project tables, constraints, indexes, functions, triggers, RLS, policies, ACL, and the project-owned Storage configuration.

Production-only definitions now explicitly represented by the baseline include `messages` and `invite_codes`, plus factual compatibility columns and overloads present in production.

Provider-owned objects such as `spatial_ref_sys`, `pg_stat_statements`, `supabase_vault`, and the structural internals of the `auth` and `storage` schemas are not recreated as application tables/extensions. The project-owned trigger on `auth.users` and project-owned policies on `storage.objects` are retained.

## Intentionally absent legacy objects

- `pg_trgm`
- `badges`
- `user_badges`
- `collections`
- `collection_locations`
- `location_media`
- `place_conditions`
- `posts`
- `route_members`
- `route_stops`
- `xp_events`

These objects are absent from factual production and are not required by current Flutter database calls or current production functions/triggers.

Only the `avatars` and `location_images` buckets are bootstrapped. The legacy `location-media` bucket is not included. Four factual storage policies named `All Access 31i9xw_*` reference an absent `places_photos` bucket; the policies are preserved to match the catalog, but that bucket is intentionally not created.

## SECURITY HARDENING REQUIRED AFTER BASELINE

The baseline intentionally reproduces factual ACL rather than silently changing security semantics. The audit found:

- several `SECURITY DEFINER` RPC functions grant execute to `anon`;
- bounded travel RPC functions retain `PUBLIC` execute;
- four broad legacy-named Storage policies target `places_photos`, a bucket not included in the canonical bucket set.

These findings require a separate reviewed hardening migration after baseline reconciliation. They must not be folded into the factual baseline.

## KNOWN FOLLOW-UP ISSUES

1. `lib/controllers/profile_controller.dart` contains a stale reference to `public.users`, which is absent from production and the baseline.
2. `supabase/functions/discovery-route/index.ts` calls the absent RPC `nearby_discovery_candidates`.

Neither stale reference is used to expand the canonical baseline. They require separate application/Edge Function work.

## Deployment invariant

The baseline is a bootstrap migration for a new environment. It must not be executed against the existing production schema. After explicit approval, only version `202608290000` should be recorded as applied in remote migration history; the first SQL planned afterward must be `202608290001_reference_filters_v2.sql`.
