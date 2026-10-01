#!/usr/bin/env bash
# Journey media LIFETIME-INVARIANT concurrency test (Phase 1H-E1 remediation R1).
#
# Proves, with three real PostgreSQL sessions and NO timing assumptions, that no
# interleaving lets a media INSERT commit against a parent that changed under it:
#
#   S2  holds advisory lock 7001 (a test-only gate).
#   S1  inserts a route_media row (as service_role). A test-only trigger that
#       fires AFTER the migration's validation blocks on that gate -- i.e. S1 is
#       frozen exactly between "validated against route R / waypoint W" and the
#       foreign-key check/commit. S3 starts only once pg_locks shows S1 waiting.
#   S3  then tries, in the frozen window, to (a) re-home the parent, (b) DELETE
#       the parent, (c) DELETE and RECREATE the parent under the same id for
#       another owner.
#   Releasing the gate lets S1 finish; the final state is inspected.
#
# Expected with the migration:  (a) rejected by the identity guard (42501),
# (b)/(c) blocked by the validation's FOR KEY SHARE (lock_not_available 55P03),
# S1 commits a consistent row.
# With a variant that lacks the row locks (negative control) (c) succeeds and
# S1 commits a media row whose owner no longer matches its route.
#
# Needs Docker. Throwaway container only. Usage (repo root, Git Bash on Windows):
#   MSYS_NO_PATHCONV=1 bash supabase/functions/moderate-content/journey_media_concurrency_test.sh [migration.sql] [expect: locked|racy]
set -u
cd "$(dirname "$0")/../../.."
MIG="${1:-supabase/migrations/202609180001_journey_media_backend.sql}"
EXPECT="${2:-locked}"
C=tm_pg_conc
PSQL="docker exec -i $C psql -U postgres -At -v ON_ERROR_STOP=1"

docker rm -f $C >/dev/null 2>&1
docker run -d --name $C -e POSTGRES_PASSWORD=x postgis/postgis:15-3.4-alpine >/dev/null
for i in $(seq 1 30); do docker exec $C psql -U postgres -c "select 1" >/dev/null 2>&1 && break; sleep 2; done
sleep 3
docker cp supabase/migrations/202609140002_trips_gps_core.sql $C:/tmp/m1.sql
docker cp supabase/migrations/202609140004_gps_table_acl_hardening.sql $C:/tmp/m2.sql
docker cp supabase/migrations/202609170001_gps_sync_backend_contract.sql $C:/tmp/m3.sql
docker cp "$MIG" $C:/tmp/mig.sql

$PSQL >/dev/null <<'SQL'
create extension if not exists postgis;
create schema auth; create schema storage;
create role authenticated nologin; create role anon nologin; create role service_role nologin bypassrls;
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema storage grant all on tables to anon, authenticated, service_role;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function storage.foldername(name text) returns text[] language sql as $$ select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
create function storage.filename(name text) returns text language sql as $$ select (string_to_array(name,'/'))[array_length(string_to_array(name,'/'),1)] $$;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
grant usage on schema auth, storage, public to authenticated, anon, service_role;
create table public.profiles (id uuid primary key);
SQL
$PSQL -f /tmp/m1.sql >/dev/null && $PSQL -f /tmp/m2.sql >/dev/null && $PSQL -f /tmp/m3.sql >/dev/null && $PSQL -f /tmp/mig.sql >/dev/null || { echo "FAIL setup"; exit 1; }

A=aaaaaaaa-0000-4000-8000-000000000001
B=bbbbbbbb-0000-4000-8000-000000000002
R=c0c0c0c0-0000-4000-8000-0000000000c0
W=0c0c0c0c-0000-4000-8000-0000000000c0
M=99999999-9999-4999-8999-999999999990

$PSQL >/dev/null <<SQL
insert into public.profiles values ('$A'), ('$B');
insert into public.recorded_routes (id, owner_id, started_at) values ('$R', '$A', now());
insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at)
  values ('$W', '$R', '$A', 'custom', 'SRID=4326;POINT(30 50)', now());
-- test-only gate: fires AFTER route_media_protect_system_fields (alphabetical order)
create function public.t_gate() returns trigger language plpgsql as \$\$
begin perform pg_advisory_xact_lock(7001); return new; end \$\$;
create trigger route_media_zz_gate before insert on public.route_media
  for each row execute function public.t_gate();
SQL

# S2: hold the gate.
docker exec -i $C psql -U postgres -At -c "select pg_advisory_lock(7001); select pg_sleep(120)" >/dev/null 2>&1 &
S2=$!
for i in $(seq 1 50); do
  n=$($PSQL -c "select count(*) from pg_locks where locktype='advisory' and objid=7001 and granted")
  [ "$n" = "1" ] && break; sleep 0.2
done
[ "$n" = "1" ] || { echo "FAIL gate not held"; exit 1; }

# S1: validated insert, frozen in the trigger.
docker exec -i $C psql -U postgres -At -c "set role service_role; insert into public.route_media (id, recorded_route_id, owner_id, waypoint_id, captured_at) values ('$M', '$R', '$A', '$W', now())" >/tmp/s1.out 2>&1 &
S1=$!
for i in $(seq 1 100); do
  n=$($PSQL -c "select count(*) from pg_locks where locktype='advisory' and objid=7001 and not granted")
  [ "$n" = "1" ] && break; sleep 0.2
done
[ "$n" = "1" ] || { echo "FAIL S1 never reached the gate"; exit 1; }
echo "S1 is frozen after validation (waiting on the gate)"

attempt() {  # label, sql  -> prints sqlstate or ok
  local out
  out=$(docker exec -i $C psql -U postgres -At -c "set lock_timeout='1500ms'; set role service_role; $2" 2>&1)
  if echo "$out" | grep -q "lock timeout"; then echo "$1 -> 55P03 (blocked by lock)"
  elif echo "$out" | grep -qi "immutable"; then echo "$1 -> 42501 (identity guard)"
  elif echo "$out" | grep -qi "ERROR"; then echo "$1 -> ERROR $(echo "$out" | head -1 | cut -c1-80)"
  else echo "$1 -> SUCCEEDED"; fi
}
RES_A=$(attempt "(a) re-home route to B     " "update public.recorded_routes set owner_id = '$B' where id = '$R'")
RES_B=$(attempt "(b) delete the route       " "delete from public.recorded_routes where id = '$R'")
RES_C=$(attempt "(c) delete+recreate for B  " "begin; delete from public.recorded_routes where id = '$R'; insert into public.recorded_routes (id, owner_id, started_at) values ('$R', '$B', now()); insert into public.route_waypoints (id, recorded_route_id, owner_id, waypoint_type, position, recorded_at) values ('$W', '$R', '$B', 'custom', 'SRID=4326;POINT(30 50)', now()); commit")
echo "$RES_A"; echo "$RES_B"; echo "$RES_C"

# Release the gate (terminate S2's session -> advisory lock freed), let S1 finish.
docker exec $C psql -U postgres -At -c "select pg_terminate_backend(pid) from pg_stat_activity where query like 'select pg_advisory_lock(7001)%' and pid <> pg_backend_pid()" >/dev/null
wait $S1 2>/dev/null; kill $S2 2>/dev/null
echo "S1 result: $(tr -d '\n' </tmp/s1.out | cut -c1-120)"
FINAL=$($PSQL -c "select coalesce((select 'media_owner=' || m.owner_id || ' route_owner=' || r.owner_id || ' consistent=' || (m.owner_id = r.owner_id) from public.route_media m join public.recorded_routes r on r.id = m.recorded_route_id where m.id = '$M'), 'no media row')")
echo "FINAL: $FINAL"

rc=0
if [ "$EXPECT" = "locked" ]; then
  echo "$RES_A" | grep -q "42501"  || { echo "FAIL (a) must be rejected by the guard"; rc=1; }
  echo "$RES_B" | grep -q "55P03"  || { echo "FAIL (b) must be blocked by the row lock"; rc=1; }
  echo "$RES_C" | grep -q "55P03"  || { echo "FAIL (c) must be blocked by the row lock"; rc=1; }
  echo "$FINAL" | grep -q "consistent=true" || { echo "FAIL final media row must be consistent"; rc=1; }
  [ $rc -eq 0 ] && echo "PASS lifetime invariant holds under concurrency"
else
  echo "$RES_C" | grep -q "SUCCEEDED" || { echo "FAIL control: expected the race to be exposed"; rc=1; }
  echo "$FINAL" | grep -q "consistent=false" || { echo "FAIL control: expected an inconsistent row"; rc=1; }
  [ $rc -eq 0 ] && echo "PASS negative control: without the row locks the race is real"
fi
docker rm -f $C >/dev/null 2>&1
exit $rc
