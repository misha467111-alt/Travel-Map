import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const sql = readFileSync(
  new URL(
    '../../migrations/202609170001_gps_sync_backend_contract.sql',
    import.meta.url,
  ),
  'utf8',
)

// ---------------------------------------------------------------------------
// Existence / signature
// ---------------------------------------------------------------------------

test('sync_route_points is created with the expected signature', () => {
  assert.match(
    sql,
    /create or replace function public\.sync_route_points\(\s*p_recorded_route_id uuid,\s*p_points jsonb\s*\)\s*returns integer/,
  )
})

test('sync_route_events is created with the expected signature', () => {
  assert.match(
    sql,
    /create or replace function public\.sync_route_events\(\s*p_recorded_route_id uuid,\s*p_events jsonb\s*\)\s*returns integer/,
  )
})

// ---------------------------------------------------------------------------
// Security mode -- SECURITY INVOKER, not DEFINER, per the explicit
// architectural decision that no privilege gap justifies DEFINER here
// (unlike finalize_recorded_route).
// ---------------------------------------------------------------------------

test('sync_route_points is SECURITY INVOKER, never SECURITY DEFINER', () => {
  const start = sql.indexOf('function public.sync_route_points(')
  const body = sql.slice(start, sql.indexOf('$$;', start) + 3)
  assert.match(body, /security invoker/)
  assert.doesNotMatch(body, /security definer/)
})

test('sync_route_events is SECURITY INVOKER, never SECURITY DEFINER', () => {
  const start = sql.indexOf('function public.sync_route_events(')
  const body = sql.slice(start, sql.indexOf('$$;', start) + 3)
  assert.match(body, /security invoker/)
  assert.doesNotMatch(body, /security definer/)
})

test('both sync RPCs pin search_path', () => {
  const points = sql.slice(
    sql.indexOf('function public.sync_route_points('),
    sql.indexOf('$$;', sql.indexOf('function public.sync_route_points(')),
  )
  const events = sql.slice(
    sql.indexOf('function public.sync_route_events('),
    sql.indexOf('$$;', sql.indexOf('function public.sync_route_events(')),
  )
  assert.match(points, /set search_path to 'public', 'pg_catalog'/)
  assert.match(events, /set search_path to 'public', 'pg_catalog'/)
})

// ---------------------------------------------------------------------------
// Explicit EXECUTE grants/revokes for both RPCs.
// ---------------------------------------------------------------------------

test('sync_route_points has an explicit revoke-then-grant EXECUTE contract', () => {
  assert.match(
    sql,
    /revoke all on function public\.sync_route_points\(uuid, jsonb\) from public, anon;/,
  )
  assert.match(
    sql,
    /grant execute on function public\.sync_route_points\(uuid, jsonb\) to authenticated;/,
  )
})

test('sync_route_events has an explicit revoke-then-grant EXECUTE contract', () => {
  assert.match(
    sql,
    /revoke all on function public\.sync_route_events\(uuid, jsonb\) from public, anon;/,
  )
  assert.match(
    sql,
    /grant execute on function public\.sync_route_events\(uuid, jsonb\) to authenticated;/,
  )
})

// ---------------------------------------------------------------------------
// Ownership -- caller identity must come from auth.uid(), never a trusted
// payload field. Neither function accepts owner_id/user_id as a param.
// ---------------------------------------------------------------------------

test('neither RPC accepts a caller-supplied owner/user identity parameter', () => {
  assert.doesNotMatch(sql, /p_owner_id/)
  assert.doesNotMatch(sql, /p_user_id/)
})

test('both RPCs verify ownership via auth.uid() against recorded_routes.owner_id', () => {
  const matches = sql.match(/where id = p_recorded_route_id and owner_id = auth\.uid\(\)/g) || []
  assert.equal(matches.length, 2)
})

// ---------------------------------------------------------------------------
// Geography construction -- server-side only, from validated lat/lng.
// ---------------------------------------------------------------------------

test('sync_route_points constructs geography server-side via ST_MakePoint, never accepts raw geography from the client', () => {
  assert.match(
    sql,
    /st_setsrid\(st_makepoint\(t\.longitude, t\.latitude\), 4326\)::geography/,
  )
})

test('sync_route_points validates latitude/longitude bounds explicitly', () => {
  const start = sql.indexOf('function public.sync_route_points(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  assert.match(body, /t\.latitude < -90 or t\.latitude > 90/)
  assert.match(body, /t\.longitude < -180 or t\.longitude > 180/)
})

// ---------------------------------------------------------------------------
// Duplicate-seq-within-batch validation.
// ---------------------------------------------------------------------------

test('sync_route_points rejects a batch with duplicate seq values', () => {
  const start = sql.indexOf('function public.sync_route_points(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  assert.match(body, /count\(distinct seq\)/)
  assert.match(body, /duplicate seq values within submitted point batch/)
})

test('sync_route_events rejects a batch with duplicate seq values', () => {
  const start = sql.indexOf('function public.sync_route_events(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  assert.match(body, /count\(distinct seq\)/)
  assert.match(body, /duplicate seq values within submitted event batch/)
})

// ---------------------------------------------------------------------------
// Conflicting-retry detection -- a submitted row at an existing seq with
// DIFFERENT data must abort the whole call, never silently win/lose.
// ---------------------------------------------------------------------------

test('sync_route_points detects a conflicting retry (existing seq, different payload) and aborts', () => {
  const start = sql.indexOf('function public.sync_route_points(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  assert.match(body, /v_conflict_count/)
  assert.match(body, /is distinct from t\.latitude|st_y\(rp\.position::geometry\) is distinct from t\.latitude/)
  assert.match(body, /point batch conflicts with already-persisted data/)
})

test('sync_route_events detects a conflicting retry (existing seq, different payload) and aborts', () => {
  const start = sql.indexOf('function public.sync_route_events(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  assert.match(body, /v_conflict_count/)
  assert.match(body, /re\.event_type is distinct from t\.event_type/)
  assert.match(body, /re\.occurred_at is distinct from t\.occurred_at/)
  assert.match(body, /event batch conflicts with already-persisted data/)
})

// ---------------------------------------------------------------------------
// Atomic batch semantics -- the explicitly forbidden naive shape must not
// appear anywhere in this file, and every conflict check must run before
// any insert (validate-then-insert, not insert-then-hope).
// ---------------------------------------------------------------------------

test('neither RPC uses the forbidden naive "insert ... on conflict do nothing, return max(seq)" shape', () => {
  // Only the actual SQL code matters here -- the file's own header comment
  // legitimately names this exact forbidden phrase in prose while
  // explaining why it was rejected, so comment lines are excluded first.
  const codeOnly = sql
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n')
    .toLowerCase()
  assert.doesNotMatch(codeOnly, /on conflict do nothing/)
  assert.doesNotMatch(codeOnly, /on conflict\s*\([^)]*\)\s*do nothing/)
})

test('sync_route_points validates (duplicate-seq, field bounds, conflicting retry) before its INSERT statement', () => {
  const start = sql.indexOf('function public.sync_route_points(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  const duplicateSeqIdx = body.indexOf('duplicate seq values within submitted point batch')
  const conflictIdx = body.indexOf('point batch conflicts with already-persisted data')
  const insertIdx = body.indexOf('insert into public.route_points')
  assert.ok(duplicateSeqIdx > -1 && conflictIdx > -1 && insertIdx > -1)
  assert.ok(duplicateSeqIdx < insertIdx)
  assert.ok(conflictIdx < insertIdx)
})

test('sync_route_events validates (duplicate-seq, field bounds, conflicting retry) before its INSERT statement', () => {
  const start = sql.indexOf('function public.sync_route_events(')
  const body = sql.slice(start, sql.indexOf('$$;', start))
  const duplicateSeqIdx = body.indexOf('duplicate seq values within submitted event batch')
  const conflictIdx = body.indexOf('event batch conflicts with already-persisted data')
  const insertIdx = body.indexOf('insert into public.recorded_route_events')
  assert.ok(duplicateSeqIdx > -1 && conflictIdx > -1 && insertIdx > -1)
  assert.ok(duplicateSeqIdx < insertIdx)
  assert.ok(conflictIdx < insertIdx)
})

test('the returned cursor is bounded to max(seq) of the submitted batch, never a global/table-wide max', () => {
  const matches = sql.match(/select max\(t\.seq\) into v_max_batch_seq\s*\n\s*from jsonb_to_recordset/g) || []
  assert.equal(matches.length, 2)
  assert.doesNotMatch(sql, /select max\(seq\) into v_max_batch_seq\s*\n\s*from public\.route_points/)
  assert.doesNotMatch(sql, /select max\(seq\) into v_max_batch_seq\s*\n\s*from public\.recorded_route_events/)
})

// ---------------------------------------------------------------------------
// Terminal-route write guard.
// ---------------------------------------------------------------------------

test('a terminal-route write guard function exists and is revoked from every client-facing role', () => {
  assert.match(
    sql,
    /create or replace function public\.enforce_recorded_route_not_terminal\(\)/,
  )
  assert.match(
    sql,
    /revoke all on function public\.enforce_recorded_route_not_terminal\(\) from public, anon, authenticated;/,
  )
})

test('the terminal-route guard treats exactly completed and discarded as terminal, matching recorded_routes_status_check', () => {
  const start = sql.indexOf('function public.enforce_recorded_route_not_terminal()')
  const body = sql.slice(start, sql.indexOf('$$;', start) + 3)
  assert.match(body, /v_status in \('completed', 'discarded'\)/)
})

test('the terminal-route guard is installed as a BEFORE INSERT trigger on route_points', () => {
  assert.match(
    sql,
    /create trigger route_points_enforce_not_terminal\s*\nbefore insert on public\.route_points\s*\nfor each row execute function public\.enforce_recorded_route_not_terminal\(\);/,
  )
})

test('the terminal-route guard is installed as a BEFORE INSERT trigger on recorded_route_events', () => {
  assert.match(
    sql,
    /create trigger recorded_route_events_enforce_not_terminal\s*\nbefore insert on public\.recorded_route_events\s*\nfor each row execute function public\.enforce_recorded_route_not_terminal\(\);/,
  )
})

test('the terminal-route guard is table-level (trigger-based), not merely checked inside the RPCs -- '
  + 'authenticated already has a direct INSERT grant on both tables, so an RPC-only check would be bypassable', () => {
  // Both RPCs additionally pre-check status themselves (for a clean error
  // message), but the trigger is what makes the invariant unbypassable
  // via a direct table INSERT. Assert both layers are present.
  assert.match(sql, /v_route\.status in \('completed', 'discarded'\)/g)
  assert.match(sql, /before insert on public\.route_points/)
  assert.match(sql, /before insert on public\.recorded_route_events/)
})

// ---------------------------------------------------------------------------
// No Activity Events wiring, no XP mutation -- explicitly out of scope for
// Phase 3B.
// ---------------------------------------------------------------------------

test('this migration adds no Activity Events wiring', () => {
  // Checks actual code constructs, not prose -- the file's own header
  // comment legitimately names activity_events/_record_activity_event/
  // ROUTE_RECORDED_COMPLETED while explaining that none of them are
  // touched, so a bare substring match would false-positive on that
  // sentence. perform/select of the helper, or a literal insert into the
  // table, would be the actual wiring this test guards against.
  assert.doesNotMatch(sql, /perform\s+public\._record_activity_event/i)
  assert.doesNotMatch(sql, /select\s+public\._record_activity_event/i)
  assert.doesNotMatch(sql, /insert into public\.activity_events/i)
  assert.doesNotMatch(sql, /from public\.activity_events/i)
})

test('this migration performs no XP mutation of any kind', () => {
  // Checks actual code constructs, not prose -- the file's own header
  // comment legitimately mentions "public.profiles.xp" while explaining
  // that it is NOT touched, so a bare substring match would false-positive
  // on that sentence.
  assert.doesNotMatch(sql, /update\s+public\.profiles/i)
  assert.doesNotMatch(sql, /from\s+public\.profiles/i)
  assert.doesNotMatch(sql, /set\s+xp\s*=/i)
  assert.doesNotMatch(sql, /\bxp_awarded\b/)
})

// ---------------------------------------------------------------------------
// No unrelated schema/RLS/grant changes to existing GPS objects.
// ---------------------------------------------------------------------------

test('this migration does not alter finalize_recorded_route, existing tables, or existing RLS policies', () => {
  assert.doesNotMatch(sql, /alter table/i)
  assert.doesNotMatch(sql, /create policy/)
  assert.doesNotMatch(sql, /drop policy/)
  assert.doesNotMatch(sql, /finalize_recorded_route\(p_recorded_route_id/)
})
