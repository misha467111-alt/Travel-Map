import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildOpenAIRequest,
  classifyProviderError,
  moderationGate,
  parseModerationResult,
  parseOpenAIResponse,
} from './validation.ts'

const valid = (decision = 'approve') => ({ decision, confidence: 0.8, reason_codes: ['safe'], short_reason: 'Valid' })

for (const decision of ['approve', 'review', 'reject']) {
  test(`accepts ${decision}`, () => assert.equal(parseModerationResult(valid(decision)).decision, decision))
}

test('rejects malformed and extra fields', () => {
  assert.throws(() => parseModerationResult('bad'), /invalid_schema/)
  assert.throws(() => parseModerationResult({ ...valid(), extra: true }), /invalid_schema/)
})

test('rejects invalid decisions', () => assert.throws(() => parseModerationResult(valid('allow')), /invalid_decision/))

test('rejects confidence outside zero to one', () => {
  assert.throws(() => parseModerationResult({ ...valid(), confidence: -0.1 }), /invalid_confidence/)
  assert.throws(() => parseModerationResult({ ...valid(), confidence: 1.1 }), /invalid_confidence/)
})

test('rejects malformed reason codes and long reasons', () => {
  assert.throws(() => parseModerationResult({ ...valid(), reason_codes: ['Not valid'] }), /invalid_reason_codes/)
  assert.throws(() => parseModerationResult({ ...valid(), short_reason: 'x'.repeat(281) }), /invalid_short_reason/)
})

test('classifies timeout, network and internal failures', () => {
  assert.equal(classifyProviderError(new DOMException('timeout', 'TimeoutError')), 'timeout')
  assert.equal(classifyProviderError(new DOMException('aborted', 'AbortError')), 'timeout')
  assert.equal(classifyProviderError(new TypeError('fetch failed')), 'network_failure')
  assert.equal(classifyProviderError(new Error('unexpected')), 'internal_error')
})

test('builds the OpenAI Responses API request with strict JSON Schema', () => {
  const body = buildOpenAIRequest(
    { title: 'Kyiv viewpoint', description: 'A scenic place', category: 'nature' },
    ' gpt-5.4-nano ',
  )
  assert.equal(body.model, 'gpt-5.4-nano')
  assert.equal(typeof body.input, 'string')
  assert.deepEqual(JSON.parse(body.input), {
    title: 'Kyiv viewpoint',
    description: 'A scenic place',
    category: 'nature',
  })
  assert.equal(body.text.format.type, 'json_schema')
  assert.equal(body.text.format.strict, true)
  assert.equal(body.text.format.schema.additionalProperties, false)
})

const completedResponse = (text) => ({
  status: 'completed',
  output: [{
    type: 'message',
    role: 'assistant',
    content: [{ type: 'output_text', text }],
  }],
})

test('accepts a completed OpenAI response with valid output_text', () => {
  assert.equal(parseOpenAIResponse(completedResponse(JSON.stringify(valid()))).decision, 'approve')
})

test('rejects valid JSON with an invalid moderation schema', () => {
  assert.throws(
    () => parseOpenAIResponse(completedResponse(JSON.stringify({ ...valid(), decision: 'allow' }))),
    /invalid_decision/,
  )
})

test('rejects a completed response without output_text', () => {
  assert.throws(
    () => parseOpenAIResponse({ status: 'completed', output: [] }),
    /missing_output_text/,
  )
})

test('rejects malformed JSON in output_text', () => {
  assert.throws(() => parseOpenAIResponse(completedResponse('{bad')), /malformed_json/)
})

test('rejects incomplete OpenAI responses', () => {
  assert.throws(() => parseOpenAIResponse({ status: 'incomplete', output: [] }), /provider_incomplete/)
})

for (const status of ['failed', 'cancelled']) {
  test(`rejects OpenAI response status ${status}`, () => {
    assert.throws(() => parseOpenAIResponse({ status, output: [] }), new RegExp(`provider_${status}`))
  })
}

test('rejects OpenAI refusals without accepting alternate output', () => {
  assert.throws(
    () => parseOpenAIResponse({
      status: 'completed',
      output: [{
        type: 'message',
        role: 'assistant',
        content: [{ type: 'refusal', refusal: 'Unable to comply' }],
      }],
    }),
    /provider_refusal/,
  )
})

test('allows moderation with no previous successful audit', () => {
  assert.deepEqual(moderationGate('pending', null), { allowed: true })
})

test('allows retry when previous attempts are errors', () => {
  // The targeted lookup returns null when no successful audit exists.
  assert.deepEqual(moderationGate('pending', null), { allowed: true })
})

test('blocks approved and rejected locations by status', () => {
  assert.equal(moderationGate('approved', 'approve').code, 'already_moderated')
  assert.equal(moderationGate('rejected', 'reject').code, 'already_moderated')
})

test('blocks pending locations sent to manual review', () => {
  assert.deepEqual(moderationGate('pending', 'review'), {
    allowed: false,
    status: 409,
    code: 'moderation_manual_review_required',
  })
})
