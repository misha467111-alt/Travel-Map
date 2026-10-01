import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

// Phase 1H-E1 backend contract for remote Journey media. Static assertions
// over the migration text (the same style as gps_sync_contract_test.mjs).
// The runtime behavior of the same SQL is exercised by
// journey_media_behavior_test.sql (see its header for how to run it against
// a throwaway Postgres).
const sql = readFileSync(
  new URL('../../migrations/202609180001_journey_media_backend.sql', import.meta.url),
  'utf8',
)

// Strip `--` comments so assertions never match explanatory prose.
const code = sql
  .split('\n')
  .map((line) => line.replace(/--.*$/, ''))
  .join('\n')

const tableBody = code.slice(
  code.indexOf('create table public.route_media'),
  code.indexOf(');', code.indexOf('create table public.route_media')),
)

// ---------------------------------------------------------------------------
// Table shape
// ---------------------------------------------------------------------------

test('B09 identity: id is the primary key (same local UUID -> same row)', () => {
  assert.match(tableBody, /id uuid primary key/)
})

test('route_media has exactly the justified columns', () => {
  for (const column of [
    'id',
    'recorded_route_id',
    'owner_id',
    'waypoint_id',
    'media_type',
    'captured_at',
    'position',
    'created_at',
  ]) {
    assert.match(tableBody, new RegExp(`\\n\\s*${column} `), column)
  }
})

test('no redundant or local-only columns are stored', () => {
  for (const banned of [
    'storage_path',
    'local_relative_path',
    'sync_status',
    'updated_at',
    'thumbnail',
    'width',
    'height',
    'size_bytes',
    'hash',
  ]) {
    assert.doesNotMatch(tableBody, new RegExp(banned), banned)
  }
})

test('ownership and parent FKs cascade, and reference the right tables', () => {
  assert.match(
    tableBody,
    /recorded_route_id uuid not null\s+references public\.recorded_routes\(id\) on delete cascade/,
  )
  assert.match(
    tableBody,
    /owner_id uuid not null\s+references public\.profiles\(id\) on delete cascade/,
  )
  assert.match(
    tableBody,
    /waypoint_id uuid\s+references public\.route_waypoints\(id\) on delete cascade/,
  )
})

test('B19 media_type is constrained and position is standalone-only', () => {
  assert.match(tableBody, /check \(media_type in \('image'\)\)/)
  assert.match(tableBody, /check \(waypoint_id is null or position is null\)/)
  assert.match(tableBody, /position geography\(Point, 4326\)/)
})

// ---------------------------------------------------------------------------
// Integrity trigger (does not rely on RLS alone)
// ---------------------------------------------------------------------------

const triggerFn = code.slice(
  code.indexOf('function public.protect_route_media_system_fields'),
  code.indexOf('$$;', code.indexOf('function public.protect_route_media_system_fields')),
)

test('trigger is SECURITY INVOKER with a pinned search_path', () => {
  assert.match(triggerFn, /security invoker/)
  assert.doesNotMatch(triggerFn, /security definer/)
  assert.match(triggerFn, /set search_path to 'public', 'pg_catalog'/)
})

test('trigger stamps owner_id from auth.uid() for authenticated callers', () => {
  assert.match(triggerFn, /current_user = 'authenticated'/)
  assert.match(triggerFn, /new\.owner_id := auth\.uid\(\)/)
})

test('B04 trigger requires the route owner to equal the media owner', () => {
  assert.match(triggerFn, /from public\.recorded_routes r/)
  assert.match(triggerFn, /v_route_owner is distinct from new\.owner_id/)
})

test('B05/B06 trigger requires the waypoint to share route AND owner', () => {
  assert.match(triggerFn, /w\.recorded_route_id = new\.recorded_route_id/)
  assert.match(triggerFn, /w\.owner_id = new\.owner_id/)
})

test('F1 trigger rejects UPDATE for EVERY role, not only authenticated', () => {
  const update = triggerFn.slice(triggerFn.indexOf("if tg_op = 'UPDATE' then"))
  const branch = update.slice(0, update.indexOf('end if;'))
  assert.match(branch, /route media is immutable once recorded/)
  assert.match(branch, /raise exception/)
  assert.doesNotMatch(branch, /current_user/, 'the UPDATE rejection must not be role-conditional')
  assert.doesNotMatch(branch, /return new/, 'no role may fall through and update')
})

test('trigger fires for insert and update and is not executable by clients', () => {
  assert.match(
    code,
    /create trigger route_media_protect_system_fields\s+before insert or update on public\.route_media\s+for each row execute function public\.protect_route_media_system_fields\(\)/,
  )
  assert.match(
    code,
    /revoke all on function public\.protect_route_media_system_fields\(\)\s+from public, anon, authenticated/,
  )
})

test('terminal-route semantics: no route status check anywhere in the migration', () => {
  assert.doesNotMatch(code, /status/)
  assert.doesNotMatch(code, /'completed'|'discarded'|'recording'/)
})

// ---------------------------------------------------------------------------
// RLS and grants
// ---------------------------------------------------------------------------

test('RLS is enabled and only select/insert/delete policies exist', () => {
  assert.match(code, /alter table public\.route_media enable row level security/)
  const policies = [...code.matchAll(/create policy (route_media_\w+) on public\.route_media\s+for (\w+)/g)]
  assert.deepEqual(
    policies.map((m) => [m[1], m[2]]),
    [
      ['route_media_select', 'select'],
      ['route_media_insert', 'insert'],
      ['route_media_delete', 'delete'],
    ],
  )
})

test('B02/B03 select and delete are owner-only', () => {
  assert.match(
    code,
    /route_media_select on public\.route_media\s+for select to authenticated\s+using \(owner_id = \(select auth\.uid\(\)\)\)/,
  )
  assert.match(
    code,
    /route_media_delete on public\.route_media\s+for delete to authenticated\s+using \(owner_id = \(select auth\.uid\(\)\)\)/,
  )
})

test('B04-B07 insert policy checks owner, owned route and same-route waypoint', () => {
  const policy = code.slice(
    code.indexOf('create policy route_media_insert'),
    code.indexOf('create policy route_media_delete'),
  )
  assert.match(policy, /owner_id = \(select auth\.uid\(\)\)/)
  assert.match(policy, /r\.owner_id = \(select auth\.uid\(\)\)/)
  assert.match(policy, /w\.recorded_route_id = route_media\.recorded_route_id/)
  assert.match(policy, /w\.owner_id = \(select auth\.uid\(\)\)/)
})

test('B20 no UPDATE policy or UPDATE grant exists for route_media', () => {
  assert.doesNotMatch(code, /create policy route_media_\w+ on public\.route_media\s+for update/)
  assert.doesNotMatch(code, /grant[^;]*\bupdate\b[^;]*on table public\.route_media/)
})

test('grants are column-scoped for insert; owner_id/created_at are never client-writable', () => {
  assert.match(code, /grant select, delete on table public\.route_media to authenticated/)
  const inserts = [...code.matchAll(/grant insert \((\w+)\) on table public\.route_media to authenticated/g)].map(
    (m) => m[1],
  )
  assert.deepEqual(inserts, ['id', 'recorded_route_id', 'waypoint_id', 'media_type', 'captured_at', 'position'])
  assert.doesNotMatch(code, /grant[^;]*truncate/i)
})

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

test('B11 the bucket is private, JPEG-only and size-limited', () => {
  assert.match(
    code,
    /insert into storage\.buckets \(id, name, public, file_size_limit, allowed_mime_types\)\s+values \('journey_media', 'journey_media', false, 5242880, array\['image\/jpeg'\]\)/,
  )
})

const storageCode = code.slice(code.indexOf('drop policy if exists journey_media_owner_insert'))

test('only INSERT, SELECT and DELETE Storage policies exist (B16: no overwrite)', () => {
  const policies = [...storageCode.matchAll(/create policy (journey_media_\w+) on storage\.objects\s+for (\w+)/g)]
  assert.deepEqual(
    policies.map((m) => [m[1], m[2]]),
    [
      ['journey_media_owner_insert', 'insert'],
      ['journey_media_owner_select', 'select'],
      ['journey_media_owner_delete', 'delete'],
    ],
  )
  assert.doesNotMatch(storageCode, /for update/)
})

test('B12-B15 insert policy pins bucket, namespace, depth, owned route and filename', () => {
  const insert = storageCode.slice(
    storageCode.indexOf('create policy journey_media_owner_insert'),
    storageCode.indexOf('drop policy if exists journey_media_owner_select'),
  )
  assert.match(insert, /bucket_id = 'journey_media'/)
  assert.match(insert, /\(storage\.foldername\(name\)\)\[1\] = \(select auth\.uid\(\)\)::text/)
  assert.match(insert, /array_length\(storage\.foldername\(name\), 1\) = 2/)
  assert.match(insert, /r\.id::text = \(storage\.foldername\(name\)\)\[2\]/)
  assert.match(insert, /r\.owner_id = \(select auth\.uid\(\)\)/)
  assert.match(
    insert,
    /\^\[0-9a-f\]\{8\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{12\}\\\.jpg\$/,
  )
})

test('B17/B18 select and delete are scoped to the caller\'s own namespace', () => {
  for (const name of ['select', 'delete']) {
    const start = storageCode.indexOf(`create policy journey_media_owner_${name}`)
    const body = storageCode.slice(start, storageCode.indexOf(';', start))
    assert.match(body, /bucket_id = 'journey_media'/, name)
    assert.match(body, /\(storage\.foldername\(name\)\)\[1\] = \(select auth\.uid\(\)\)::text/, name)
  }
})

// ---------------------------------------------------------------------------
// B21 / B22: nothing existing is touched
// ---------------------------------------------------------------------------

test('B21/B22 only the two narrow parent identity guards touch existing objects', () => {
  // No schema, grant, policy, constraint or data change on any existing table.
  assert.doesNotMatch(code, /alter table public\.(?!route_media)/)
  assert.doesNotMatch(code, /alter policy/)
  assert.doesNotMatch(code, /drop table|drop function/)
  assert.doesNotMatch(code, /\b(update|delete from|truncate)\s+public\./i)
  for (const untouched of [
    'avatars',
    'location_images',
    'places_photos',
    'route_points',
    'recorded_route_events',
    'finalize_recorded_route',
    'sync_route_points',
    'sync_route_events',
    'protect_recorded_route_system_fields',
    'protect_route_waypoint_system_fields',
  ]) {
    assert.doesNotMatch(code, new RegExp(untouched), untouched)
  }
  // Every statement against recorded_routes / route_waypoints is one of the two guard triggers.
  const onParents = [
    ...code.matchAll(/(?:create trigger|drop trigger if exists) (\w+)(?: on public\.(recorded_routes|route_waypoints)|\s+before update on public\.(recorded_routes|route_waypoints))/g),
  ].map((m) => m[1])
  assert.deepEqual(
    [...new Set(onParents)].sort(),
    ['recorded_routes_identity_guard', 'route_waypoints_identity_guard'],
  )
  assert.doesNotMatch(code, /on public\.(recorded_routes|route_waypoints)\s+for (select|insert|update|delete)/)
  assert.doesNotMatch(code, /grant[^;]*on table public\.(recorded_routes|route_waypoints)/)
  assert.doesNotMatch(code, /revoke[^;]*on table public\.(recorded_routes|route_waypoints)/)
  const drops = [...code.matchAll(/drop policy if exists (\w+) on ([\w.]+)/g)].map((m) => m[1])
  for (const name of drops) {
    assert.match(name, /^(route_media|journey_media)_/, name)
  }
})

// ---------------------------------------------------------------------------
// R1: parent identity guards -- the lifetime invariant
// ---------------------------------------------------------------------------

const routeGuard = code.slice(
  code.indexOf('function public.guard_recorded_route_identity'),
  code.indexOf('$$;', code.indexOf('function public.guard_recorded_route_identity')),
)
const waypointGuard = code.slice(
  code.indexOf('function public.guard_route_waypoint_identity'),
  code.indexOf('$$;', code.indexOf('function public.guard_route_waypoint_identity')),
)

test('R1 recorded_routes guard compares id and owner_id (OLD vs NEW)', () => {
  assert.match(routeGuard, /new\.id is distinct from old\.id/)
  assert.match(routeGuard, /new\.owner_id is distinct from old\.owner_id/)
  assert.match(routeGuard, /errcode = '42501'/)
})

test('R1 route_waypoints guard compares id, owner_id and recorded_route_id', () => {
  assert.match(waypointGuard, /new\.id is distinct from old\.id/)
  assert.match(waypointGuard, /new\.owner_id is distinct from old\.owner_id/)
  assert.match(waypointGuard, /new\.recorded_route_id is distinct from old\.recorded_route_id/)
  assert.match(waypointGuard, /errcode = '42501'/)
})

test('R1 guards are role-independent: no current_user / role-name test', () => {
  for (const body of [routeGuard, waypointGuard]) {
    assert.doesNotMatch(body, /current_user|session_user|auth\.role|service_role|authenticated/)
  }
})

test('R1 guards guard ONLY identity columns, never status/derived/sync fields', () => {
  for (const body of [routeGuard, waypointGuard]) {
    for (const mutable of ['status', 'ended_at', 'total_distance_m', 'title', 'note', 'sync', 'updated_at', 'photo_ref']) {
      assert.doesNotMatch(body, new RegExp(mutable), mutable)
    }
  }
})

test('R1 guards are SECURITY INVOKER, pin search_path and are not client-callable', () => {
  for (const body of [routeGuard, waypointGuard]) {
    assert.match(body, /security invoker/)
    assert.doesNotMatch(body, /security definer/)
    assert.match(body, /set search_path to 'public', 'pg_catalog'/)
  }
  assert.match(code, /revoke all on function public\.guard_recorded_route_identity\(\)\s+from public, anon, authenticated/)
  assert.match(code, /revoke all on function public\.guard_route_waypoint_identity\(\)\s+from public, anon, authenticated/)
})

test('R1 guard triggers are plain BEFORE UPDATE (not column-list scoped) on each parent', () => {
  assert.match(
    code,
    /create trigger recorded_routes_identity_guard\s+before update on public\.recorded_routes\s+for each row execute function public\.guard_recorded_route_identity\(\)/,
  )
  assert.match(
    code,
    /create trigger route_waypoints_identity_guard\s+before update on public\.route_waypoints\s+for each row execute function public\.guard_route_waypoint_identity\(\)/,
  )
  assert.doesNotMatch(code, /before update of/)
})

test('R1 media validation locks the parent rows (FOR KEY SHARE) against concurrent delete', () => {
  assert.equal([...triggerFn.matchAll(/for key share/g)].length, 2)
  assert.match(triggerFn, /from public\.recorded_routes r\s+where r\.id = new\.recorded_route_id\s+for key share/)
  assert.match(triggerFn, /w\.owner_id = new\.owner_id\s+for key share/)
})

test('R1 the migration documents the lifetime invariant and the honest existing-table impact', () => {
  assert.match(sql, /LIFETIME INVARIANT/)
  assert.match(sql, /EXISTING-TABLE IMPACT \(the only one\)/)
  assert.match(sql, /No column, grant,\s+--\s+policy, constraint or data of either table is changed/)
  assert.match(sql, /There is no\s+--\s+repair RPC and no service_role escape hatch/)
  assert.doesNotMatch(sql, /deliberately does not touch/)
})

test('only the three trigger functions are created; no RPC, no Edge Function', () => {
  const functions = [...code.matchAll(/create (?:or replace )?function ([\w.]+)/g)].map((m) => m[1])
  assert.deepEqual(functions, [
    'public.protect_route_media_system_fields',
    'public.guard_recorded_route_identity',
    'public.guard_route_waypoint_identity',
  ])
})

// ---------------------------------------------------------------------------
// Honest documentation (F3 / F4 / F5): the migration must not overstate what
// the backend guarantees, and must record the deferred items.
// ---------------------------------------------------------------------------

test('F3 the comments make no unprovable overwrite/retry claims', () => {
  for (const overstated of [
    /can never be overwritten/i,
    /cannot succeed for anyone/i,
    /already-synced after verifying/i,
    /overwrite is never the retry mechanism/i,
  ]) {
    assert.doesNotMatch(sql, overstated)
  }
})

test('F3 the retry contract states what is guaranteed and what is not', () => {
  assert.match(sql, /GUARANTEED by this migration/)
  assert.match(sql, /NOT guaranteed/)
  assert.match(sql, /upsert:false/)
  assert.match(sql, /DELETE followed by a new INSERT of the same path is a\s+--\s+separate, permitted operation/)
  assert.match(sql, /Phase 1H-E2 must reconcile database metadata and object\s+--\s+state before acknowledging a retry as synced/)
})

test('F4 orphaned Storage objects are recorded as explicit deferred debt', () => {
  assert.match(sql, /ORPHANED STORAGE OBJECTS \(F4\)/)
  assert.match(sql, /can never delete\s+--\s+Storage objects/)
  assert.match(sql, /FUTURE WORK/)
  assert.doesNotMatch(code, /cron|pg_net|http_|edge/i)
})

test('F5 the MIME allowlist is documented as NOT content validation', () => {
  assert.match(sql, /NOT content validation/)
  assert.match(sql, /not a security boundary/)
})
