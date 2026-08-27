# Travel

Social discovery app built with Flutter, Riverpod, GoRouter, Supabase and PostGIS.

## Run locally

1. Create a Supabase project and run `supabase db push`.
2. Configure Google/Apple providers and callback `io.supabase.travelmap://login-callback/`.
3. Put Google Maps keys in the native Android/iOS configuration.
4. Run without committing credentials:

```powershell
flutter run --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=ANON_KEY `
  --dart-define=GOOGLE_MAPS_API_KEY=MAPS_KEY
```

The anon key is designed for client use, but authorization is enforced by RLS. Never ship the service-role key.

## Architecture

New features use `lib/features/<feature>/{domain,data,presentation}`. Domain code is Flutter/Supabase independent; repositories hide network and cache implementations; Riverpod wires dependencies. The existing prototype UI remains available while screens are migrated feature-by-feature.

Server-authoritative operations live in PostgreSQL RPC functions. In particular, `create_check_in` validates authentication, GPS accuracy, the 100 m PostGIS distance, daily uniqueness and XP in one transaction. Clients cannot insert check-ins or XP events directly.

## Backend

- `supabase/migrations`: PostGIS schema, spatial/search indexes, RLS, Storage and Realtime.
- `supabase/functions/moderate-content`: authenticated adapter for a text/image moderation provider.
- `supabase/functions/discovery-route`: authenticated discovery candidate selection.

Set Edge Function secrets with `supabase secrets set MODERATION_API_URL=... MODERATION_API_KEY=...` and deploy with `supabase functions deploy`.

## Production checklist

- Use separate development/staging/production Supabase projects.
- Enable leaked-password protection, rate limits and database backups.
- Configure Crashlytics/Sentry and consent-aware analytics.
- Review map-tile/offline licensing; Google Maps tiles cannot be cached arbitrarily.
- Add an admin moderation queue and device E2E tests before release.
