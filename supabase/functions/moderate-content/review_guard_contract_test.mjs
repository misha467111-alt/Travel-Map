import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')

test('audit lookup is targeted, successful-only, newest-first and bounded', () => {
  assert.match(source, /\.eq\('location_id', locationId\)/)
  assert.match(source, /\.eq\('attempt_status', 'succeeded'\)/)
  assert.match(source, /\.order\('created_at', \{ ascending: false \}\)/)
  assert.match(source, /\.limit\(1\)/)
})

test('manual-review guard runs before failure audit and provider fetch', () => {
  const gate = source.indexOf('const gate = moderationGate')
  const failureAudit = source.indexOf('const recordFailure')
  const providerCall = source.indexOf('await fetch(providerUrl')
  assert.ok(gate > 0 && gate < failureAudit && failureAudit < providerCall)
})

test('manual-review response is deterministic and creates no audit', () => {
  assert.match(source, /return json\(\{ status: location\.status, error: gate\.code \}, gate\.status\)/)
  assert.doesNotMatch(
    source.slice(source.indexOf('const gate = moderationGate'), source.indexOf('const recordFailure')),
    /record_location_moderation_result/,
  )
})

test('database claim happens before provider call and blocks competitors', () => {
  const claim = source.indexOf("'try_claim_location_moderation'")
  const providerCall = source.indexOf('await fetch(providerUrl')
  assert.ok(claim > 0 && claim < providerCall)
  assert.match(source, /error: 'moderation_in_progress'/)
})
