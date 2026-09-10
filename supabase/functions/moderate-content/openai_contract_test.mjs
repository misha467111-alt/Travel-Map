import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')

test('provider request uses the configured Responses API endpoint and trusted DB content', () => {
  assert.match(source, /await fetch\(providerUrl/)
  assert.match(source, /buildOpenAIRequest\(location, model\)/)
  assert.match(source, /\.select\('id,owner_id,title,description,category,status'\)/)
  assert.doesNotMatch(source, /payload\?\.(title|description|category|image_url)/)
})

test('HTTP 401, 429 and 500 all take the provider failure pending path', () => {
  assert.match(source, /if \(!providerResponse\.ok\)/)
  assert.match(source, /await recordFailure\('provider_failure'\)/)
  assert.match(source, /return json\(\{ status: 'pending', error: 'provider_failure' \}, 502\)/)
})

test('timeout uses a 12-second AbortController and always clears its timer', () => {
  assert.match(source, /const controller = new AbortController\(\)/)
  assert.match(source, /setTimeout\(\(\) => controller\.abort\(\), 12_000\)/)
  assert.match(source, /signal: controller\.signal/)
  assert.match(source, /finally \{\s*clearTimeout\(timeoutId\)/)
})

test('provider failures are audited as errors so the location remains retryable', () => {
  assert.match(source, /p_attempt_status: 'error'/)
  assert.match(source, /p_decision: null/)
  assert.match(source, /p_confidence: null/)
  assert.match(source, /return json\(\{ status: 'pending'/)
})
