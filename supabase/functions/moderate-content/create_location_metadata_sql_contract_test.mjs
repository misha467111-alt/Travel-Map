import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const sql = readFileSync(
  new URL(
    '../../migrations/202609160001_create_location_metadata_and_rollback_cleanup.sql',
    import.meta.url,
  ),
  'utf8',
)

test('widened create_location_with_xp preserves the original 7 required parameters, in order', () => {
  assert.match(
    sql,
    /create function public\.create_location_with_xp\(\s*location_title text,\s*location_description text,\s*location_latitude double precision,\s*location_longitude double precision,\s*p_image_url text,\s*p_category text,\s*p_request_id uuid,/,
  )
})

test('the 4 new parameters are all optional and default to null', () => {
  assert.match(sql, /p_address text default null/)
  assert.match(sql, /p_amenities text\[\] default null/)
  assert.match(sql, /p_opening_hours jsonb default null/)
  assert.match(sql, /p_timezone text default null/)
})

test('the old 7-argument function is DROPped, not left alongside a second overload', () => {
  assert.match(
    sql,
    /drop function if exists public\.create_location_with_xp\(\s*text, text, double precision, double precision, text, text, uuid\s*\);/,
  )
  // Exactly one `create function public.create_location_with_xp(` -- if a
  // second overload were ever added here instead of replacing the first,
  // this count would be 2 and the existing named-argument call from
  // LocationsRepository.createLocation would become ambiguous.
  const matches = sql.match(/create function public\.create_location_with_xp\(/g) ?? []
  assert.equal(matches.length, 1)
})

test('submission is still pending and still does not award XP', () => {
  const createBody = sql.split('create function public.create_location_with_xp')[1]
  assert.match(createBody, /'pending','public','pending'/)
  assert.doesNotMatch(createBody, /set xp\s*=/i)
})

test('the insert carries the new metadata columns through unchanged from the params', () => {
  const createBody = sql.split('create function public.create_location_with_xp')[1]
  assert.match(createBody, /address,amenities,opening_hours,timezone/)
  assert.match(
    createBody,
    /nullif\(btrim\(p_address\),''\),p_amenities,p_opening_hours,p_timezone/,
  )
})

test('request_id idempotency short-circuit is preserved verbatim', () => {
  const createBody = sql.split('create function public.create_location_with_xp')[1]
  assert.match(
    createBody,
    /select id into location_id from public\.locations where owner_id=uid and request_id=p_request_id;\s*if location_id is not null then return location_id; end if;/,
  )
})

test('create_location_with_xp grants match the intended privilege model', () => {
  const createGrants = sql.split(
    'grant execute on function public.create_location_with_xp(',
  )[1]
  assert.match(
    sql,
    /revoke all on function public\.create_location_with_xp\(\s*text, text, double precision, double precision, text, text, uuid,\s*text, text\[\], jsonb, text\s*\) from public, anon;/,
  )
  assert.match(createGrants, /to authenticated, service_role;/)
})

test('cleanup RPC only ever deletes the caller\'s own pending row for the exact request that created it', () => {
  const cleanupBody = sql.split(
    'create function public.cleanup_own_pending_location_create_failure',
  )[1]
  assert.match(cleanupBody, /security definer/)
  assert.match(cleanupBody, /if uid is null then raise exception 'authentication required'; end if;/)
  assert.match(cleanupBody, /and owner_id = uid/)
  assert.match(cleanupBody, /and request_id = p_request_id/)
  assert.match(cleanupBody, /and status = 'pending';/)
  // Must never be able to touch draft/approved/rejected rows -- only the
  // literal string 'pending' may appear as a status filter in this body.
  assert.doesNotMatch(cleanupBody, /status = 'approved'/)
  assert.doesNotMatch(cleanupBody, /status = 'draft'/)
  assert.doesNotMatch(cleanupBody, /status = 'rejected'/)
})

test('cleanup RPC grants match the intended privilege model', () => {
  assert.match(
    sql,
    /revoke all on function public\.cleanup_own_pending_location_create_failure\(\s*uuid, uuid\s*\) from public, anon;/,
  )
  assert.match(
    sql,
    /grant execute on function public\.cleanup_own_pending_location_create_failure\(\s*uuid, uuid\s*\) to authenticated, service_role;/,
  )
})

test('does not touch the legacy 6-argument overload or update_own_location', () => {
  assert.doesNotMatch(sql, /create_location_with_xp\(text,text,double precision,double precision,text,text\)/)
  assert.doesNotMatch(sql, /update_own_location/)
})
