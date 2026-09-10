export type ModerationDecision = 'approve' | 'review' | 'reject'

export interface ModerationResult {
  decision: ModerationDecision
  confidence: number
  reason_codes: string[]
  short_reason: string
}

export interface TrustedLocationContent {
  title: string
  description: string | null
  category: string | null
}

export const OPENAI_MODERATION_INSTRUCTIONS = `You moderate a user-submitted travel location for publication.
Return approve when the content appears safe, relevant to travel, and suitable for publication.
Return review when it is ambiguous, suspicious, or uncertain and needs human review.
Return reject only for a clear violation, including dangerous or illegal content, sexual or extremely inappropriate content, hate or extremist content, threats or incitement to violence, spam or scams, or clearly meaningless or travel-irrelevant content.
When uncertain, choose review rather than reject. Do not perform or request database operations.`

export function buildOpenAIRequest(location: TrustedLocationContent, model: string) {
  return {
    model: model.trim(),
    instructions: OPENAI_MODERATION_INSTRUCTIONS,
    input: JSON.stringify({
      title: location.title,
      description: location.description,
      category: location.category,
    }),
    text: {
      format: {
        type: 'json_schema',
        name: 'location_moderation',
        strict: true,
        schema: {
          type: 'object',
          additionalProperties: false,
          properties: {
            decision: { type: 'string', enum: ['approve', 'review', 'reject'] },
            confidence: { type: 'number', minimum: 0, maximum: 1 },
            reason_codes: {
              type: 'array',
              maxItems: 20,
              items: { type: 'string', pattern: '^[a-z0-9_:-]{1,64}$' },
            },
            short_reason: { type: 'string', maxLength: 280 },
          },
          required: ['decision', 'confidence', 'reason_codes', 'short_reason'],
        },
      },
    },
  }
}

export function parseOpenAIResponse(value: unknown): ModerationResult {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('invalid_provider_response')
  }
  const response = value as Record<string, unknown>
  if (response.status !== 'completed') {
    const status = typeof response.status === 'string' ? response.status : 'unknown'
    throw new Error(`provider_${status}`)
  }
  if (!Array.isArray(response.output)) throw new Error('missing_output_text')

  let outputText: string | null = null
  for (const item of response.output) {
    if (typeof item !== 'object' || item === null || Array.isArray(item)) continue
    const outputItem = item as Record<string, unknown>
    if (outputItem.type !== 'message' || outputItem.role !== 'assistant' || !Array.isArray(outputItem.content)) continue
    for (const content of outputItem.content) {
      if (typeof content !== 'object' || content === null || Array.isArray(content)) continue
      const part = content as Record<string, unknown>
      if (part.type === 'refusal') throw new Error('provider_refusal')
      if (part.type === 'output_text' && typeof part.text === 'string' && outputText === null) {
        outputText = part.text
      }
    }
  }
  if (outputText === null) throw new Error('missing_output_text')

  let parsed: unknown
  try {
    parsed = JSON.parse(outputText)
  } catch {
    throw new Error('malformed_json')
  }
  return parseModerationResult(parsed)
}

export function classifyProviderError(error: unknown): string {
  if (error instanceof DOMException && ['AbortError', 'TimeoutError'].includes(error.name)) return 'timeout'
  if (error instanceof TypeError) return 'network_failure'
  return 'internal_error'
}

export type ModerationGate =
  | { allowed: true }
  | { allowed: false; status: 409; code: 'already_moderated' | 'moderation_manual_review_required' }

export function moderationGate(
  status: string,
  latestSuccessfulDecision: string | null,
): ModerationGate {
  if (status !== 'pending') {
    return { allowed: false, status: 409, code: 'already_moderated' }
  }
  if (latestSuccessfulDecision === 'review') {
    return {
      allowed: false,
      status: 409,
      code: 'moderation_manual_review_required',
    }
  }
  return { allowed: true }
}

export function parseModerationResult(value: unknown): ModerationResult {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error('invalid_schema')
  const record = value as Record<string, unknown>
  const keys = Object.keys(record).sort()
  const expected = ['confidence', 'decision', 'reason_codes', 'short_reason']
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) throw new Error('invalid_schema')
  if (!['approve', 'review', 'reject'].includes(String(record.decision))) throw new Error('invalid_decision')
  if (typeof record.confidence !== 'number' || !Number.isFinite(record.confidence) || record.confidence < 0 || record.confidence > 1) throw new Error('invalid_confidence')
  if (!Array.isArray(record.reason_codes) || record.reason_codes.length > 20 || record.reason_codes.some((code) => typeof code !== 'string' || !/^[a-z0-9_:-]{1,64}$/.test(code))) throw new Error('invalid_reason_codes')
  if (typeof record.short_reason !== 'string' || record.short_reason.trim().length > 280) throw new Error('invalid_short_reason')
  return {
    decision: record.decision as ModerationDecision,
    confidence: record.confidence,
    reason_codes: record.reason_codes,
    short_reason: record.short_reason.trim(),
  }
}
