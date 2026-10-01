-- Journey media backend BEHAVIOR test (Phase 1H-E1).
--
-- Exercises supabase/migrations/202609180001_journey_media_backend.sql for
-- real (RLS, the integrity trigger, column grants, Storage policies) as two
-- different authenticated users. It is NOT run against the Supabase project:
-- it needs a THROWAWAY Postgres with PostGIS, and it builds minimal shims for
-- auth.uid(), storage.* and the parent tables, so every assertion runs
-- against a disposable database.
--
-- Run (Docker), from the repository root (the three GPS migrations are the REAL parents):
--   docker run -d --name tm_pg_test -e POSTGRES_PASSWORD=x postgis/postgis:15-3.4-alpine
--   docker cp supabase/migrations/202609140002_trips_gps_core.sql tm_pg_test:/tmp/m_gps_core.sql
--   docker cp supabase/migrations/202609140004_gps_table_acl_hardening.sql tm_pg_test:/tmp/m_gps_acl.sql
--   docker cp supabase/migrations/202609170001_gps_sync_backend_contract.sql tm_pg_test:/tmp/m_gps_sync.sql
--   docker cp supabase/migrations/202609180001_journey_media_backend.sql tm_pg_test:/tmp/migration.sql
--   docker cp supabase/functions/moderate-content/journey_media_behavior_test.sql tm_pg_test:/tmp/test.sql
--   docker exec tm_pg_test psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/test.sql
--   (optional negative controls: add -v attack_demo=1, or -v mut_grant_option=1 / mut_col_grant_option=1 /
--    mut_col_update=1 / mut_table_update=1 / mut_new_grantee=1 / mut_policy=1 -- the inventory must then FAIL)
--   docker rm -f tm_pg_test
-- Every check prints "PASS <label>"; any failure raises and stops.
--
-- WHAT THIS PROVES, AND WHAT IT DOES NOT
--   PROVEN (real PostgreSQL, real RLS/grants/trigger code, run as authenticated,
--   service_role and the table owner against the hosted platform's DEFAULT
--   PRIVILEGES and a BYPASSRLS service_role): table privileges, RLS, the
--   integrity/immutability trigger, constraints, and the Storage policy
--   EXPRESSIONS.
--   NOT PROVEN (labelled "[shim]"): hosted Storage API behavior. storage.objects
--   here is a stand-in table; upsert handling, size/mime enforcement, signed URLs
--   and the HTTP mapping of policy failures must be verified against the real
--   service after apply.
--
-- POST-APPLY LIVE CHECK (read-only; run with `supabase db query --linked`):
--   select grantee::regrole::text, privilege_type
--     from pg_class c, aclexplode(c.relacl) x
--    where c.oid = 'public.route_media'::regclass and x.grantee <> c.relowner
--    order by 1, 2;
--   -- expected: authenticated DELETE/SELECT; service_role DELETE/INSERT/SELECT.
--   select policyname, cmd, permissive from pg_policies
--    where (schemaname = 'public' and tablename = 'route_media')
--       or (schemaname = 'storage' and tablename = 'objects' and policyname like 'journey_media_%')
--    order by 1;
--   -- expected: exactly the six policies listed in this migration, nothing broader.
--   select id, public, file_size_limit, allowed_mime_types from storage.buckets
--    where id = 'journey_media';   -- public = false
-- (On Git Bash for Windows prefix the docker commands with MSYS_NO_PATHCONV=1.)
--
\set ON_ERROR_STOP 1
create extension if not exists postgis;

-- ---- minimal Supabase-shaped environment (shims, test-only) ----
create schema auth;
create schema storage;
create role authenticated nologin;
create role anon nologin;
-- service_role bypasses RLS on the hosted platform (rolbypassrls = true, verified live).
create role service_role nologin bypassrls;
-- The hosted platform's DEFAULT PRIVILEGES (pg_default_acl, verified live) grant ALL on
-- every new public/storage table to anon, authenticated and service_role. Reproduce them
-- BEFORE any table exists so the migration is tested against the real privilege
-- environment, not a cleaned-up one.
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema storage
  grant all on tables to anon, authenticated, service_role;
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table storage.buckets (id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid, unique (bucket_id, name));
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language plpgsql as $$
declare p text[]; begin p := string_to_array(name, '/'); return p[1:array_length(p,1)-1]; end $$;
create function storage.filename(name text) returns text language plpgsql as $$
declare p text[]; begin p := string_to_array(name, '/'); return p[array_length(p,1)]; end $$;
grant usage on schema auth, storage, public to authenticated, anon, service_role;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;

-- The ONLY stand-in parent is profiles (the auth-linked user table). The GPS parents
-- (recorded_routes, route_waypoints and their protect triggers, RLS, grants, the real
-- finalize_recorded_route(), route_points/events) are the ACTUAL repository migrations,
-- applied verbatim. Their function definitions were verified byte-identical to the
-- live project (md5 of pg_get_functiondef) when this harness was written.
create table public.profiles (id uuid primary key);
\i /tmp/m_gps_core.sql
\i /tmp/m_gps_acl.sql
\i /tmp/m_gps_sync.sql

-- Snapshot of everything about the two existing parents BEFORE the migration, so the
-- end of this suite can prove the migration changed nothing on them except adding the
-- two identity-guard triggers (table ACL, column ACLs, policies, trigger set).
create table zz_pre_parent as
select c.relname,
       c.relacl::text as acl,
       (select string_agg(a.attname || ':' || coalesce(a.attacl::text, ''), ',' order by a.attnum)
          from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as cols,
       (select string_agg(p.polname || ':' || p.polcmd::text || ':' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
                          || ':' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''), ',' order by p.polname)
          from pg_policy p where p.polrelid = c.oid) as pol,
       (select string_agg(t.tgname, ',' order by t.tgname)
          from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) as trg
from pg_class c
where c.oid in ('public.recorded_routes'::regclass, 'public.route_waypoints'::regclass);

-- ---- the migration under test, verbatim ----
\i /tmp/migration.sql

-- ---- fixtures (inserted as the table owner, like a migration/seed) ----
insert into public.profiles values
  ('aaaaaaaa-0000-4000-8000-000000000001'), ('bbbbbbbb-0000-4000-8000-000000000002');
insert into public.recorded_routes (id, owner_id, started_at) values
  ('a1a1a1a1-0000-4000-8000-0000000000a1', 'aaaaaaaa-0000-4000-8000-000000000001', now()),
  ('a2a2a2a2-0000-4000-8000-0000000000a2', 'aaaaaaaa-0000-4000-8000-000000000001', now()),
  ('b1b1b1b1-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-000000000002', now());
insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at) values
  ('0a0a0a0a-0000-4000-8000-0000000000a1', 'a1a1a1a1-0000-4000-8000-0000000000a1', 'aaaaaaaa-0000-4000-8000-000000000001', 'custom', 'SRID=4326;POINT(30 50)', now()),
  ('0a0a0a0a-0000-4000-8000-0000000000a2', 'a2a2a2a2-0000-4000-8000-0000000000a2', 'aaaaaaaa-0000-4000-8000-000000000001', 'custom', 'SRID=4326;POINT(30 50)', now()),
  ('0b0b0b0b-0000-4000-8000-0000000000b1', 'b1b1b1b1-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-000000000002', 'custom', 'SRID=4326;POINT(30 50)', now());

create function t_as(uid uuid, stmt text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  set local role authenticated;
  execute stmt;
  reset role;
  return 'ok';
exception when others then
  reset role;
  return sqlstate;
end $$;

create function t_n(uid uuid, stmt text) returns bigint language plpgsql as $$
declare n bigint;
begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  set local role authenticated;
  execute stmt into n;
  reset role;
  return n;
end $$;

create function expect(label text, got anyelement, want anyelement) returns void language plpgsql as $$
begin
  if got is distinct from want then
    raise exception 'FAIL %: got %, wanted %', label, got, want;
  end if;
  raise notice 'PASS %', label;
end $$;

do $t$
declare
  a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  b uuid := 'bbbbbbbb-0000-4000-8000-000000000002';
  rA text := 'a1a1a1a1-0000-4000-8000-0000000000a1';
  rA2 text := 'a2a2a2a2-0000-4000-8000-0000000000a2';
  rB text := 'b1b1b1b1-0000-4000-8000-0000000000b1';
  m1 text := '11111111-1111-4111-8111-111111111111';
  m2 text := '22222222-2222-4222-8222-222222222222';
  m3 text := '33333333-3333-4333-8333-333333333333';
begin
  -- B01/B08 standalone with position
  perform expect('B01/B08 standalone media accepted', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, captured_at, position)
       values (%L, %L, now(), 'SRID=4326;POINT(30.5 50.4)')$q$, m1, rA)), 'ok');
  -- B07 valid Moment attachment
  perform expect('B07 Moment attachment accepted', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, waypoint_id, captured_at)
       values (%L, %L, %L, now())$q$, m2, rA, '0a0a0a0a-0000-4000-8000-0000000000a1')), 'ok');
  -- owner stamped from auth.uid()
  perform expect('owner stamped server-side', (select owner_id from route_media where id = m1::uuid), a);
  -- B10 duplicate id
  perform expect('B10 duplicate id rejected', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, captured_at) values (%L, %L, now())$q$, m1, rA)), '23505');
  -- client cannot supply owner_id
  perform expect('client owner_id not grantable', t_as(a, format(
    $q$insert into route_media (id, owner_id, recorded_route_id, captured_at)
       values (%L, %L, %L, now())$q$, m3, b, rA)), '42501');
  -- B02 other owner cannot read
  perform expect('B02 other owner reads nothing', t_n(b, 'select count(*) from route_media'), 0::bigint);
  perform expect('B02 owner reads own', t_n(a, 'select count(*) from route_media'), 2::bigint);
  -- B03 other owner cannot delete
  perform expect('B03 other owner delete affects 0', t_n(b,
    $q$with d as (delete from route_media returning 1) select count(*) from d$q$), 0::bigint);
  perform expect('B03 rows still there', (select count(*) from route_media), 2::bigint);
  -- B04 other owner inserts against this route
  perform expect('B04 other owner insert against route rejected', t_as(b, format(
    $q$insert into route_media (id, recorded_route_id, captured_at) values (%L, %L, now())$q$, m3, rA)), '42501');
  -- B05 waypoint from another route
  perform expect('B05 wrong-route waypoint rejected', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, waypoint_id, captured_at)
       values (%L, %L, %L, now())$q$, m3, rA, '0a0a0a0a-0000-4000-8000-0000000000a2')), '42501');
  -- B06 waypoint of another owner
  perform expect('B06 wrong-owner waypoint rejected', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, waypoint_id, captured_at)
       values (%L, %L, %L, now())$q$, m3, rA, '0b0b0b0b-0000-4000-8000-0000000000b1')), '42501');
  -- trigger itself (privileged writer, no RLS)
  begin
    insert into route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
      values (m3::uuid, rA::uuid, a, '0b0b0b0b-0000-4000-8000-0000000000b1', now());
    raise exception 'FAIL trigger allowed cross-owner waypoint for a privileged writer';
  exception when sqlstate '42501' then raise notice 'PASS B05/B06 trigger enforces integrity for privileged writers too';
  end;
  begin
    insert into route_media (id, recorded_route_id, owner_id, captured_at)
      values (m3::uuid, rB::uuid, a, now());
    raise exception 'FAIL trigger allowed a route owned by someone else';
  exception when sqlstate '42501' then raise notice 'PASS trigger rejects owner != route owner for privileged writers';
  end;
  -- B19 position semantics
  perform expect('B19 attached media with position rejected', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, waypoint_id, captured_at, position)
       values (%L, %L, %L, now(), 'SRID=4326;POINT(1 1)')$q$, m3, rA, '0a0a0a0a-0000-4000-8000-0000000000a1')), '23514');
  perform expect('B19 standalone without position accepted', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, captured_at) values (%L, %L, now())$q$, m3, rA2)), 'ok');
  -- media_type check
  perform expect('media_type only image', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, captured_at, media_type)
       values (%L, %L, now(), 'video')$q$, '44444444-4444-4444-8444-444444444444', rA)), '23514');
  -- B20 immutability: no privilege
  perform expect('B20 update denied by ACL', t_as(a, format(
    $q$update route_media set captured_at = now() where id = %L$q$, m1)), '42501');
  -- B20 trigger as defence in depth, even if a grant were added
  grant update on public.route_media to authenticated;
  create policy tmp_upd on public.route_media for update to authenticated
    using (owner_id = auth.uid()) with check (owner_id = auth.uid());
  perform expect('B20 update trigger rejects authenticated', t_as(a, format(
    $q$update route_media set captured_at = now() where id = %L$q$, m1)), '42501');
  drop policy tmp_upd on public.route_media;
  revoke update on public.route_media from authenticated;
  -- anon has nothing
  perform expect('anon has no table access', (select count(*) from information_schema.role_table_grants
     where table_name = 'route_media' and grantee = 'anon'), 0::bigint);
  -- delete by owner works, cascades
  perform expect('owner can delete own media', t_n(a, format(
    $q$with d as (delete from route_media where id = %L returning 1) select count(*) from d$q$, m3)), 1::bigint);
  -- cascade from waypoint
  delete from public.route_waypoints where id = '0a0a0a0a-0000-4000-8000-0000000000a1';
  perform expect('waypoint delete cascades attached media', (select count(*) from route_media where id = m2::uuid), 0::bigint);

  -- ---- Storage ----
  -- SQL-SHIM behavior only: these check the policy EXPRESSIONS against a stand-in
  -- storage.objects table. Hosted Storage API behavior (upsert handling, size and
  -- mime enforcement, signed URLs, how the API maps a policy failure to HTTP) is NOT
  -- proven here and must be checked against the real service after apply.
  perform expect('B11 bucket is private', (select public from storage.buckets where id = 'journey_media'), false);
  perform expect('bucket mime types', (select allowed_mime_types from storage.buckets where id = 'journey_media'), array['image/jpeg']);
  perform expect('bucket size limit 5 MB', (select file_size_limit from storage.buckets where id = 'journey_media'), 5242880::bigint);

  perform expect('[shim] B12 valid owner path accepted', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/' || m1 || '.jpg')), 'ok');
  perform expect('[shim] B13 other owner cannot use my namespace', t_as(b, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/' || m3 || '.jpg')), '42501');
  perform expect('[shim] B14 route segment not owned by caller rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rB || '/' || m3 || '.jpg')), '42501');
  perform expect('[shim] B14 own namespace + other owner route rejected for B too', t_as(b, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, b || '/' || rA || '/' || m3 || '.jpg')), '42501');
  perform expect('[shim] B14 unknown route segment rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/not-a-route/' || m3 || '.jpg')), '42501');
  -- B15 filename / path shape
  perform expect('[shim] B15 non-uuid filename rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/photo.jpg')), '42501');
  perform expect('[shim] B15 uppercase uuid rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/' || upper('abcdefab-cdef-4abc-8def-abcdefabcdef') || '.jpg')), '42501');
  perform expect('[shim] B15 wrong extension rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/' || m3 || '.png')), '42501');
  perform expect('[shim] B15 extra nesting rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/x/' || m3 || '.jpg')), '42501');
  perform expect('[shim] B15 missing route folder rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || m3 || '.jpg')), '42501');
  perform expect('[shim] wrong bucket not covered by journey policies', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('other_bucket', %L)$q$, a || '/' || rA || '/' || m3 || '.jpg')), '42501');
  -- B16 no overwrite / update
  perform expect('[shim] B16 duplicate path (upsert:false) rejected', t_as(a, format(
    $q$insert into storage.objects (bucket_id, name) values ('journey_media', %L)$q$, a || '/' || rA || '/' || m1 || '.jpg')), '23505');
  perform expect('[shim] B16 update affects 0 rows (no UPDATE policy)', t_n(a, format(
    $q$with u as (update storage.objects set name = name where name = %L returning 1) select count(*) from u$q$,
    a || '/' || rA || '/' || m1 || '.jpg')), 0::bigint);
  -- B17 / B18
  perform expect('[shim] B17 owner reads own object', t_n(a, 'select count(*) from storage.objects where bucket_id = ''journey_media'''), 1::bigint);
  perform expect('[shim] B17 other owner reads nothing', t_n(b, 'select count(*) from storage.objects where bucket_id = ''journey_media'''), 0::bigint);
  perform expect('[shim] B18 other owner delete affects 0', t_n(b,
    $q$with d as (delete from storage.objects where bucket_id = 'journey_media' returning 1) select count(*) from d$q$), 0::bigint);
  perform expect('[shim] B18 object still present', (select count(*) from storage.objects where bucket_id = 'journey_media'), 1::bigint);
  perform expect('[shim] owner deletes own object', t_n(a,
    $q$with d as (delete from storage.objects where bucket_id = 'journey_media' returning 1) select count(*) from d$q$), 1::bigint);

  -- terminal-route semantics: media is accepted while the remote route is
  -- 'recording' (pre-finalize) AND after it is completed (retry path)
  perform expect('accepted before finalize', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, captured_at) values (%L, %L, now())$q$,
    '55555555-5555-4555-8555-555555555555', rA)), 'ok');
  update public.recorded_routes set status = 'completed' where id = rA::uuid;
  perform expect('accepted after finalize (retry)', t_as(a, format(
    $q$insert into route_media (id, recorded_route_id, captured_at) values (%L, %L, now())$q$,
    '66666666-6666-4666-8666-666666666666', rA)), 'ok');
end
$t$;

-- ===========================================================================
-- Security remediation (F1/F2): EFFECTIVE privileges, not SQL text.
-- Runs as authenticated, service_role (BYPASSRLS, default ALL grants) and the
-- table owner. Fresh ids so earlier fixtures cannot interfere.
-- ===========================================================================
create function t_asr(rolename text, uid uuid, stmt text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), true);
  execute format('set local role %I', rolename);
  execute stmt;
  reset role;
  return 'ok';
exception when others then
  reset role;
  return sqlstate;
end $$;

do $t$
declare
  a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  b uuid := 'bbbbbbbb-0000-4000-8000-000000000002';
  rA text := 'a1a1a1a1-0000-4000-8000-0000000000a1';
  rB text := 'b1b1b1b1-0000-4000-8000-0000000000b1';
  wA text := '0a0a0a0a-0000-4000-8000-0000000000a9';
  wB text := '0b0b0b0b-0000-4000-8000-0000000000b1';
  mv text := '77777777-7777-4777-8777-777777777777';
  col text;
  before_row text;
begin
  -- fixture: one standalone row owned by A, inserted as the table owner
  insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at)
    values (wA::uuid, rA::uuid, a, 'custom', 'SRID=4326;POINT(30 50)', now());
  insert into public.route_media (id, recorded_route_id, owner_id, captured_at, position)
    values (mv::uuid, rA::uuid, a, now(), 'SRID=4326;POINT(30.5 50.4)');
  before_row := (select row(m.*)::text from public.route_media m where id = mv::uuid);

  -- ---- UPDATE denied, per column, for authenticated AND service_role ----
  foreach col in array array['id', 'owner_id', 'recorded_route_id', 'waypoint_id',
                             'media_type', 'captured_at', 'created_at', 'position'] loop
    perform expect('F1 authenticated UPDATE ' || col || ' denied',
      t_asr('authenticated', a, format(
        'update public.route_media set %I = %I where id = %L', col, col, mv)), '42501');
    perform expect('F1 service_role UPDATE ' || col || ' denied',
      t_asr('service_role', null, format(
        'update public.route_media set %I = %I where id = %L', col, col, mv)), '42501');
  end loop;
  -- the specific attack from the review: re-home the row to another owner/route
  perform expect('F1 service_role cannot re-home a row to another owner/route',
    t_asr('service_role', null, format(
      $q$update public.route_media set owner_id = %L, recorded_route_id = %L where id = %L$q$, b, rB, mv)), '42501');

  -- ---- UPDATE-based UPSERT denied ----
  perform expect('F1 authenticated UPSERT (ON CONFLICT DO UPDATE) denied',
    t_asr('authenticated', a, format(
      $q$insert into public.route_media (id, recorded_route_id, captured_at)
         values (%L, %L, now()) on conflict (id) do update set captured_at = excluded.captured_at$q$, mv, rA)), '42501');
  perform expect('F1 service_role UPSERT (ON CONFLICT DO UPDATE) denied',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, captured_at)
         values (%L, %L, %L, now()) on conflict (id) do update set owner_id = excluded.owner_id$q$, mv, rB, b)), '42501');
  -- ON CONFLICT DO NOTHING stays a legal no-op (it is not an update)
  perform expect('ON CONFLICT DO NOTHING is not an UPDATE',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, captured_at)
         values (%L, %L, %L, now()) on conflict (id) do nothing$q$, mv, rA, a)), 'ok');

  -- ---- UPDATE is rejected even for the table owner (trigger, not grants) ----
  begin
    update public.route_media set captured_at = now() where id = mv::uuid;
    raise exception 'FAIL table owner UPDATE succeeded';
  exception when sqlstate '42501' then raise notice 'PASS F1 trigger rejects UPDATE for the table owner too';
  end;

  -- ---- TRUNCATE denied ----
  perform expect('F1 authenticated TRUNCATE denied', t_asr('authenticated', a, 'truncate public.route_media'), '42501');
  perform expect('F1 service_role TRUNCATE denied', t_asr('service_role', null, 'truncate public.route_media'), '42501');
  perform expect('F1 anon TRUNCATE denied', t_asr('anon', null, 'truncate public.route_media'), '42501');

  -- ---- nothing changed ----
  perform expect('F1 row is byte-for-byte unchanged after all attacks',
    (select row(m.*)::text from public.route_media m where id = mv::uuid), before_row);

  -- ---- privileged INSERT still goes through relational validation ----
  perform expect('privileged INSERT valid standalone accepted',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, captured_at)
         values (%L, %L, %L, now())$q$, '88888888-8888-4888-8888-888888888881', rA, a)), 'ok');
  perform expect('privileged INSERT valid Moment attachment accepted',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
         values (%L, %L, %L, %L, now())$q$, '88888888-8888-4888-8888-888888888882', rA, a, wA)), 'ok')
    ;
  perform expect('privileged INSERT: owner != route owner rejected',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, captured_at)
         values (%L, %L, %L, now())$q$, '88888888-8888-4888-8888-888888888883', rB, a)), '42501');
  perform expect('privileged INSERT: unknown route rejected',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, captured_at)
         values (%L, %L, %L, now())$q$, '88888888-8888-4888-8888-888888888884',
      'ffffffff-ffff-4fff-8fff-ffffffffffff', a)), '42501');
  perform expect('privileged INSERT: other owner''s waypoint rejected',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
         values (%L, %L, %L, %L, now())$q$, '88888888-8888-4888-8888-888888888885', rA, a, wB)), '42501');
  perform expect('privileged INSERT: waypoint from another route rejected',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
         values (%L, %L, %L, %L, now())$q$, '88888888-8888-4888-8888-888888888886', rB, b,
      '0a0a0a0a-0000-4000-8000-0000000000a2')), '42501');
  perform expect('privileged INSERT without owner_id rejected',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, captured_at)
         values (%L, %L, now())$q$, '88888888-8888-4888-8888-888888888887', rA)), '42501');
  perform expect('privileged INSERT: Moment + own position rejected (check)',
    t_asr('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at, position)
         values (%L, %L, %L, %L, now(), 'SRID=4326;POINT(1 1)')$q$,
      '88888888-8888-4888-8888-888888888888', rA, a, wA)), '23514');
  -- ordinary DELETE still works for each role (RLS-scoped for authenticated)
  perform expect('service_role DELETE allowed',
    t_asr('service_role', null, $q$delete from public.route_media where id = '88888888-8888-4888-8888-888888888882'$q$), 'ok');
  perform expect('authenticated owner DELETE allowed',
    t_n(a, $q$with d as (delete from public.route_media where id = '88888888-8888-4888-8888-888888888881' returning 1) select count(*) from d$q$),
    1::bigint);
end
$t$;



-- ===========================================================================
-- ATTACK DEMO (optional): psql -v attack_demo=1
-- Reproduces the independent review's cascade attack step by step and prints
-- whether each step SUCCEEDED or was BLOCKED. Meant to be run against the final
-- migration (every step blocked at the re-home) and against a deliberately
-- vulnerable variant without the parent identity guards (the attack succeeds).
-- It does not assert; the assertions are the R1 checks that follow.
-- ===========================================================================
\if :{?attack_demo}
do $t$
declare
  a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  b uuid := 'bbbbbbbb-0000-4000-8000-000000000002';
  rD uuid := 'd1d1d1d1-0000-4000-8000-0000000000d1';
  wD uuid := '0d0d0d0d-0000-4000-8000-0000000000d1';
  mD uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1';
  step1 text;
  deleted bigint;
  media_left bigint;
begin
  insert into public.recorded_routes (id, owner_id, started_at) values (rD, a, now());
  insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at)
    values (wD, rD, a, 'custom', 'SRID=4326;POINT(30 50)', now());
  insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
    values (mD, rD, a, wD, now());
  raise notice 'DEMO 0: valid media % owned by A on A''s route and A''s waypoint', mD;

  step1 := t_asr('service_role', null, format(
    'update public.recorded_routes set owner_id = %L where id = %L', b, rD));
  raise notice 'DEMO 1: service_role re-homes the route to B -> %',
    case when step1 = 'ok' then 'SUCCEEDED' else 'BLOCKED (' || step1 || ')' end;

  deleted := t_n(b, format(
    $q$with d as (delete from public.recorded_routes where id = %L returning 1) select count(*) from d$q$, rD));
  raise notice 'DEMO 2: B deletes the route as its (new) owner -> % row(s) deleted', deleted;

  select count(*) into media_left from public.route_media where id = mD;
  raise notice 'DEMO 3: A''s media row still exists? -> %',
    case when media_left = 1 then 'YES (attack blocked)' else 'NO -- cascade-deleted by B (ATTACK SUCCEEDED)' end;

  delete from public.recorded_routes where id = rD;  -- cleanup (table owner)
end
$t$;
\endif

-- ===========================================================================
-- R1: PARENT INTEGRITY (lifetime invariant), against the REAL GPS parents.
-- Identity/relationship columns of recorded_routes and route_waypoints can
-- never be re-homed -- by authenticated, service_role (BYPASSRLS, full default
-- UPDATE) or the table owner -- while every legitimate update still works.
-- ===========================================================================
create function t_err(rolename text, uid uuid, stmt text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), true);
  execute format('set local role %I', rolename);
  execute stmt;
  reset role;
  return 'ok';
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end $$;

do $t$
declare
  a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  b uuid := 'bbbbbbbb-0000-4000-8000-000000000002';
  rC text := 'c1c1c1c1-0000-4000-8000-0000000000c1';   -- A's route under test
  rC2 text := 'c2c2c2c2-0000-4000-8000-0000000000c2';  -- another route owned by A
  rB text := 'b1b1b1b1-0000-4000-8000-0000000000b1';   -- B's route
  wC text := '0c0c0c0c-0000-4000-8000-0000000000c1';   -- A's waypoint on rC
  mC text := '99999999-9999-4999-8999-999999999991';   -- valid media on rC / wC
  mS text := '99999999-9999-4999-8999-999999999992';   -- valid standalone media on rC
  snap_media text;
  snap_route text;
  snap_wp text;
  r text;
begin
  -- fixtures (table owner): A's route + waypoint + two valid media rows
  insert into public.recorded_routes (id, owner_id, started_at) values
    (rC::uuid, a, now()), (rC2::uuid, a, now());
  insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at)
    values (wC::uuid, rC::uuid, a, 'custom', 'SRID=4326;POINT(30 50)', now());
  insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
    values (mC::uuid, rC::uuid, a, wC::uuid, now());
  insert into public.route_media (id, recorded_route_id, owner_id, captured_at)
    values (mS::uuid, rC::uuid, a, now());
  snap_media := (select string_agg(m::text, ';' order by m.id) from public.route_media m where recorded_route_id = rC::uuid);
  snap_route := (select r2::text from public.recorded_routes r2 where id = rC::uuid);
  snap_wp := (select w::text from public.route_waypoints w where id = wC::uuid);

  -- ---- relationship-breaking operations: every role, every identity column ----
  foreach r in array array['service_role', 'authenticated'] loop
    perform expect('R1 ' || r || ' cannot re-home a route (owner_id)',
      t_asr(r, a, format('update public.recorded_routes set owner_id = %L where id = %L', b, rC)), '42501');
    perform expect('R1 ' || r || ' cannot change a route id',
      t_asr(r, a, format('update public.recorded_routes set id = %L where id = %L', 'c9c9c9c9-0000-4000-8000-0000000000c9', rC)), '42501');
    perform expect('R1 ' || r || ' cannot re-home a waypoint (owner_id)',
      t_asr(r, a, format('update public.route_waypoints set owner_id = %L where id = %L', b, wC)), '42501');
    perform expect('R1 ' || r || ' cannot move a waypoint to another route of the SAME owner',
      t_asr(r, a, format('update public.route_waypoints set recorded_route_id = %L where id = %L', rC2, wC)), '42501');
    perform expect('R1 ' || r || ' cannot move a waypoint to ANOTHER owner''s route',
      t_asr(r, a, format('update public.route_waypoints set recorded_route_id = %L where id = %L', rB, wC)), '42501');
    perform expect('R1 ' || r || ' cannot change a waypoint id',
      t_asr(r, a, format('update public.route_waypoints set id = %L where id = %L', '0c0c0c0c-0000-4000-8000-0000000000c9', wC)), '42501');
  end loop;
  -- The privileged paths fail because of the NEW guard (a message check, not just a code):
  perform expect('R1 service_role route re-home is rejected by the identity guard',
    t_err('service_role', null, format('update public.recorded_routes set owner_id = %L where id = %L', b, rC)),
    '42501|recorded route identity (id, owner_id) is immutable');
  perform expect('R1 service_role waypoint re-home is rejected by the identity guard',
    t_err('service_role', null, format('update public.route_waypoints set recorded_route_id = %L where id = %L', rC2, wC)),
    '42501|route waypoint identity (id, owner_id, recorded_route_id) is immutable');
  -- UPSERT variants of the same attacks
  perform expect('R1 service_role UPSERT cannot re-home a route',
    t_asr('service_role', null, format(
      $q$insert into public.recorded_routes (id, owner_id, started_at) values (%L, %L, now())
         on conflict (id) do update set owner_id = excluded.owner_id$q$, rC, b)), '42501');
  perform expect('R1 service_role UPSERT cannot re-home a waypoint',
    t_asr('service_role', null, format(
      $q$insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at)
         values (%L, %L, %L, 'custom', 'SRID=4326;POINT(1 1)', now())
         on conflict (id) do update set recorded_route_id = excluded.recorded_route_id$q$, wC, rC2, a)), '42501');
  -- even the table owner
  begin
    update public.recorded_routes set owner_id = b where id = rC::uuid;
    raise exception 'FAIL table owner re-homed a route';
  exception when sqlstate '42501' then raise notice 'PASS R1 identity guard also stops the table owner (route)';
  end;
  begin
    update public.route_waypoints set owner_id = b where id = wC::uuid;
    raise exception 'FAIL table owner re-homed a waypoint';
  exception when sqlstate '42501' then raise notice 'PASS R1 identity guard also stops the table owner (waypoint)';
  end;

  -- ---- Astra's cascade attack: blocked at the re-home step ----
  -- (re-home A's route to B, then delete as B so the cascade removes A's media)
  perform expect('R1 cascade attack step 1 (re-home) is blocked',
    t_asr('service_role', null, format('update public.recorded_routes set owner_id = %L where id = %L', b, rC)), '42501');
  perform expect('R1 cascade attack step 2: B cannot delete A''s route', t_n(b, format(
    $q$with d as (delete from public.recorded_routes where id = %L returning 1) select count(*) from d$q$, rC)), 0::bigint);
  perform expect('R1 media rows and parents are byte-for-byte unchanged after the attack', (
    (select string_agg(m::text, ';' order by m.id) from public.route_media m where recorded_route_id = rC::uuid)
    || (select r2::text from public.recorded_routes r2 where id = rC::uuid)
    || (select w::text from public.route_waypoints w where id = wC::uuid)),
    snap_media || snap_route || snap_wp);

  -- ---- legitimate non-identity updates keep working ----
  perform expect('legit: service_role updates route title/status',
    t_asr('service_role', null, format($q$update public.recorded_routes set title = 'x', status = 'paused' where id = %L$q$, rC)), 'ok');
  perform expect('legit: authenticated owner pauses/resumes (allowed transition)',
    t_asr('authenticated', a, format($q$update public.recorded_routes set status = 'recording', title = 'y' where id = %L$q$, rC)), 'ok');
  perform expect('legit: authenticated owner edits waypoint title/note/type',
    t_asr('authenticated', a, format($q$update public.route_waypoints set title = 't', note = 'n', waypoint_type = 'rest' where id = %L$q$, wC)), 'ok');
  perform expect('legit: service_role edits waypoint title/note',
    t_asr('service_role', null, format($q$update public.route_waypoints set title = 't2', note = 'n2' where id = %L$q$, wC)), 'ok');
  perform expect('legit: unchanged identity values in an UPDATE are allowed',
    t_asr('service_role', null, format($q$update public.route_waypoints set owner_id = owner_id, recorded_route_id = recorded_route_id where id = %L$q$, wC)), 'ok');
  perform expect('authenticated still cannot touch owner/derived fields (existing behavior)',
    t_asr('authenticated', a, format($q$update public.recorded_routes set total_distance_m = 1 where id = %L$q$, rC)), '42501');

  -- ---- real finalize_recorded_route() with media attached: still works ----
  insert into public.recorded_route_events (recorded_route_id, seq, event_type, occurred_at)
    values (rC::uuid, 1, 'start', now() - interval '10 minutes'), (rC::uuid, 2, 'finish', now());
  perform expect('legit: real finalize_recorded_route() runs for the owner',
    t_asr('authenticated', a, format('select public.finalize_recorded_route(%L)', rC)), 'ok');
  perform expect('finalization completed the route and left identity untouched', (
    select status || ':' || owner_id::text from public.recorded_routes where id = rC::uuid), 'completed:' || a::text);
  perform expect('finalization left the media rows untouched', (
    select string_agg(m::text, ';' order by m.id) from public.route_media m where recorded_route_id = rC::uuid), snap_media);
  perform expect('media still accepted by the (now completed) remote route', t_asr('service_role', null, format(
    $q$insert into public.route_media (id, recorded_route_id, owner_id, captured_at) values (%L, %L, %L, now())$q$,
    '99999999-9999-4999-8999-999999999993', rC, a)), 'ok');
end
$t$;

-- ===========================================================================
-- R2a: SAME OWNER, SAME-OWNER ROUTE, WAYPOINT ON A DIFFERENT ROUTE -- isolated.
-- owner correct; route owned by that owner; waypoint owned by that same owner;
-- ONLY the waypoint's route differs. Must be rejected for the waypoint/route
-- mismatch specifically (not an owner mismatch, which is a different message).
-- ===========================================================================
do $t$
declare
  a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  rA text := 'a1a1a1a1-0000-4000-8000-0000000000a1';
  wOnOtherRoute text := '0a0a0a0a-0000-4000-8000-0000000000a2'; -- owned by A, belongs to route a2a2..a2
begin
  perform expect('R2 fixture sanity: waypoint is owned by the same owner',
    (select owner_id from public.route_waypoints where id = wOnOtherRoute::uuid), a);
  perform expect('R2 fixture sanity: route is owned by the same owner',
    (select owner_id from public.recorded_routes where id = rA::uuid), a);
  perform expect('R2 fixture sanity: the waypoint belongs to a DIFFERENT route',
    (select recorded_route_id <> rA::uuid from public.route_waypoints where id = wOnOtherRoute::uuid), true);
  perform expect('R2 same-owner/wrong-route waypoint rejected for the ROUTE MISMATCH (privileged insert)',
    t_err('service_role', null, format(
      $q$insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at)
         values (%L, %L, %L, %L, now())$q$, 'aabbccdd-0000-4000-8000-0000000000e1', rA, a, wOnOtherRoute)),
    '42501|waypoint ' || wOnOtherRoute || ' does not belong to this recorded route and owner');
end
$t$;

-- ===========================================================================
-- R2b: inventory mutation hooks (negative controls). Run the suite with e.g.
--   psql -v mutation=grant_option ...
-- to inject a disposable privilege regression right before the inventory
-- checks; the inventory below must then FAIL. Never applied unless requested.
-- ===========================================================================
\if :{?mut_grant_option}
  \echo 'MUTATION INJECTED: table SELECT WITH GRANT OPTION'
  grant select on public.route_media to authenticated with grant option;
\endif
\if :{?mut_col_grant_option}
  \echo 'MUTATION INJECTED: column INSERT WITH GRANT OPTION'
  grant insert (id) on public.route_media to authenticated with grant option;
\endif
\if :{?mut_col_update}
  \echo 'MUTATION INJECTED: column UPDATE grant'
  grant update (captured_at) on public.route_media to authenticated;
\endif
\if :{?mut_table_update}
  \echo 'MUTATION INJECTED: table UPDATE grant to service_role'
  grant update on public.route_media to service_role;
\endif
\if :{?mut_new_grantee}
  \echo 'MUTATION INJECTED: unexpected grantee anon SELECT'
  grant select on public.route_media to anon;
\endif
\if :{?mut_policy}
  \echo 'MUTATION INJECTED: extra permissive policy'
  create policy mut_open on public.route_media for select to authenticated using (true);
\endif
-- ===========================================================================
-- Effective-privilege inventory: exactly what is intended, nothing else.
-- ===========================================================================
do $t$
declare
  got text;
begin
  -- Table-level grants from the ACL (grantee 0 = PUBLIC); the owner is excluded.
  select string_agg(
           (case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end)
             || ':' || x.privilege_type || ':' || (case when x.is_grantable then 'GRANTABLE' else 'plain' end),
           ', ' order by (case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end), x.privilege_type)
    into got
  from pg_class c, aclexplode(c.relacl) x
  where c.oid = 'public.route_media'::regclass
    and x.grantee <> c.relowner;
  perform expect('F2 effective TABLE grants are exactly the intended set', got,
    'authenticated:DELETE:plain, authenticated:SELECT:plain, service_role:DELETE:plain, service_role:INSERT:plain, service_role:SELECT:plain');

  -- Column-level grants (only authenticated INSERT, on exactly six columns).
  select string_agg(a.attname || ':' || x.privilege_type || ':' || (case when x.is_grantable then 'GRANTABLE' else 'plain' end), ', ' order by a.attname, x.privilege_type)
    into got
  from pg_attribute a, aclexplode(a.attacl) x
  where a.attrelid = 'public.route_media'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attacl is not null;
  perform expect('F2 effective COLUMN grants are exactly the six insert columns', got,
    'captured_at:INSERT:plain, id:INSERT:plain, media_type:INSERT:plain, position:INSERT:plain, recorded_route_id:INSERT:plain, waypoint_id:INSERT:plain');

  -- has_*_privilege agrees with the ACL for every ordinary role.
  perform expect('F2 no role has UPDATE or TRUNCATE on the table', (
    select count(*) from unnest(array['authenticated', 'service_role', 'anon']) r
    where has_table_privilege(r, 'public.route_media', 'UPDATE')
       or has_table_privilege(r, 'public.route_media', 'TRUNCATE')
       or has_table_privilege(r, 'public.route_media', 'REFERENCES')
       or has_table_privilege(r, 'public.route_media', 'TRIGGER')), 0::bigint);
  perform expect('F2 no role has column UPDATE on any column', (
    select count(*) from unnest(array['authenticated', 'service_role', 'anon']) r,
         pg_attribute a
    where a.attrelid = 'public.route_media'::regclass and a.attnum > 0 and not a.attisdropped
      and has_column_privilege(r, 'public.route_media', a.attname, 'UPDATE')), 0::bigint);
  perform expect('F2 anon has no access of any kind', (
    select count(*) from unnest(array['SELECT', 'INSERT', 'DELETE']) p
    where has_table_privilege('anon', 'public.route_media', p)), 0::bigint);
  perform expect('F2 authenticated can insert only the six columns', (
    select string_agg(a.attname, ', ' order by a.attname)
    from pg_attribute a
    where a.attrelid = 'public.route_media'::regclass and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('authenticated', 'public.route_media', a.attname, 'INSERT')),
    'captured_at, id, media_type, position, recorded_route_id, waypoint_id');

  -- Column inventory: detects an unexpected column.
  perform expect('F2 table has exactly the expected columns', (
    select string_agg(a.attname, ', ' order by a.attname)
    from pg_attribute a
    where a.attrelid = 'public.route_media'::regclass and a.attnum > 0 and not a.attisdropped),
    'captured_at, created_at, id, media_type, owner_id, position, recorded_route_id, waypoint_id');

  -- Policy inventory on the table: exactly three, all PERMISSIVE, authenticated only.
  perform expect('F2 route_media policies are exactly select/insert/delete', (
    select string_agg(policyname || ':' || cmd || ':' || permissive || ':' || roles::text, ', ' order by policyname)
    from pg_policies where schemaname = 'public' and tablename = 'route_media'),
    'route_media_delete:DELETE:PERMISSIVE:{authenticated}, route_media_insert:INSERT:PERMISSIVE:{authenticated}, route_media_select:SELECT:PERMISSIVE:{authenticated}');

  -- Policy inventory on storage.objects in this disposable environment: only
  -- the three journey_media policies exist, so any extra permissive policy
  -- that appeared here would fail this check. (Hosted Storage can carry other
  -- buckets' policies; see the post-apply live check in the header.)
  perform expect('F2 [shim] storage.objects policies are exactly the three journey_media ones', (
    select string_agg(policyname || ':' || cmd || ':' || permissive, ', ' order by policyname)
    from pg_policies where schemaname = 'storage' and tablename = 'objects'),
    'journey_media_owner_delete:DELETE:PERMISSIVE, journey_media_owner_insert:INSERT:PERMISSIVE, journey_media_owner_select:SELECT:PERMISSIVE');

  -- Trigger inventory.
  perform expect('F2 exactly one non-internal trigger, before insert or update', (
    select string_agg(tgname || ':' || (tgtype & 2)::text || ':' || (tgtype & 16)::text || ':' || (tgtype & 4)::text, ', ')
    from pg_trigger where tgrelid = 'public.route_media'::regclass and not tgisinternal),
    'route_media_protect_system_fields:2:16:4');
end
$t$;

-- ===========================================================================
-- Existing-table impact: ONLY the two identity-guard triggers were added.
-- ===========================================================================
do $t$
declare
  rec record;
  now_row record;
begin
  for rec in select * from zz_pre_parent loop
    select c.relacl::text as acl,
       (select string_agg(a.attname || ':' || coalesce(a.attacl::text, ''), ',' order by a.attnum)
          from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as cols,
       (select string_agg(p.polname || ':' || p.polcmd::text || ':' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
                          || ':' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''), ',' order by p.polname)
          from pg_policy p where p.polrelid = c.oid) as pol,
       (select string_agg(t.tgname, ',' order by t.tgname)
          from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) as trg
      into now_row
      from pg_class c where c.oid = ('public.' || rec.relname)::regclass;
    perform expect('parent ' || rec.relname || ': table ACL unchanged by the migration', now_row.acl, rec.acl);
    perform expect('parent ' || rec.relname || ': column ACLs unchanged by the migration', now_row.cols, rec.cols);
    perform expect('parent ' || rec.relname || ': policies unchanged by the migration', now_row.pol, rec.pol);
    perform expect('parent ' || rec.relname || ': triggers = previous set + exactly the identity guard', now_row.trg, (
      select string_agg(x, ',' order by x)
      from unnest(string_to_array(rec.trg, ',') || (rec.relname || '_identity_guard')) x));
  end loop;
end
$t$;
