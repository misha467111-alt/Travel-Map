-- Minimal hardening for three public-schema Security Advisor findings.
-- No data, application write RPC, auth, XP, invite rewards, or PostGIS
-- extension objects are rewritten or removed.

-- Legacy/unreachable application table: deny all direct client access.
alter table public.routes enable row level security;
revoke all privileges on table public.routes from anon, authenticated;

-- Legacy invite_codes is not the canonical invites/invite_redemptions system.
-- Keep the table for compatibility, but make it inaccessible to normal clients.
alter table public.invite_codes enable row level security;
revoke all privileges on table public.invite_codes from anon, authenticated;

-- spatial_ref_sys is intentionally not altered here: it is owned by the
-- supabase_admin-owned PostGIS extension, while the migration role is not a
-- member of that role. Ownership/schema/data changes would be unsafe.
