import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const sql = readFileSync(new URL('../../migrations/202609040002_trusted_ai_location_moderation.sql', import.meta.url), 'utf8')
const createBody = sql.split('create or replace function public.create_location_with_xp')[1]

test('submission is pending and does not award XP', () => {
  assert.match(createBody, /'pending','public','pending'/)
  assert.doesNotMatch(createBody, /set xp\s*=/i)
})

test('moderation validates state, decisions and confidence', () => {
  assert.match(sql, /p_decision not in \('approve','review','reject'\)/)
  assert.match(sql, /p_confidence < 0 or p_confidence > 1/)
  assert.match(sql, /location not found/)
  assert.match(sql, /location is not pending moderation/)
})

test('errors remain pending and successful decisions map explicitly', () => {
  assert.match(sql, /p_attempt_status='error' then 'pending'/)
  assert.match(sql, /p_decision='approve' then 'approved'/)
  assert.match(sql, /p_decision='reject' then 'rejected'/)
})

test('approval reward is guarded and atomic with moderation', () => {
  assert.match(sql, /approval_rewarded_at is not null/)
  assert.match(sql, /approval_rewarded_at=now\(\)/)
  assert.match(sql, /where id=p_location_id and approval_rewarded_at is null/)
  assert.match(sql, /set xp=coalesce\(xp,0\)\+10/)
})

test('client roles cannot execute the trusted transition', () => {
  assert.match(sql, /from public, anon, authenticated;/)
  assert.match(sql, /to service_role;/)
})

test('legacy submission overload is unavailable to client roles', () => {
  assert.match(sql, /create_location_with_xp\(text,text,double precision,double precision,text,text\)\s+from public, anon, authenticated/)
})

test('provider concurrency uses a service-only expiring database claim', () => {
  assert.match(sql, /moderation_started_at timestamptz/)
  assert.match(sql, /moderation_started_at < now\(\) - interval '2 minutes'/)
  assert.match(sql, /try_claim_location_moderation\(uuid\)[\s\S]*from public, anon, authenticated/)
  assert.match(sql, /set moderation_started_at=null/)
})
