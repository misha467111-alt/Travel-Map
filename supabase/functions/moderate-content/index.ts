import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'
import {
  buildOpenAIRequest,
  classifyProviderError,
  moderationGate,
  parseOpenAIResponse,
} from './validation.ts'

const json = (body: unknown, status = 200) => Response.json(body, { status })

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const providerUrl = Deno.env.get('AI_MODERATION_URL')
  const providerKey = Deno.env.get('AI_MODERATION_KEY')
  const model = Deno.env.get('AI_MODERATION_MODEL')
  if (!url || !anonKey || !serviceKey || !providerUrl || !providerKey || !model?.trim()) {
    return json({ error: 'server_not_configured' }, 503)
  }

  const authorization = request.headers.get('Authorization') ?? ''
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
  const { data: { user } } = await userClient.auth.getUser()
  if (!user) return json({ error: 'unauthorized' }, 401)

  let locationId: string
  try {
    const payload = await request.json()
    locationId = typeof payload?.location_id === 'string' ? payload.location_id : ''
  } catch {
    return json({ error: 'invalid_json' }, 400)
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(locationId)) {
    return json({ error: 'invalid_location_id' }, 400)
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: location, error: locationError } = await admin
    .from('locations')
    .select('id,owner_id,title,description,category,status')
    .eq('id', locationId)
    .maybeSingle()
  if (locationError) return json({ error: 'location_lookup_failed' }, 502)
  if (!location || location.owner_id !== user.id) return json({ error: 'location_not_found' }, 404)

  // Only the latest successful decision matters. Error attempts deliberately
  // do not block retry. This lookup is covered by the location/created_at index.
  const { data: latestSuccessfulAudit, error: auditLookupError } = await admin
    .from('location_moderation_audits')
    .select('decision')
    .eq('location_id', locationId)
    .eq('attempt_status', 'succeeded')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (auditLookupError) return json({ error: 'moderation_audit_lookup_failed' }, 502)

  const gate = moderationGate(location.status, latestSuccessfulAudit?.decision ?? null)
  if (!gate.allowed) {
    return json({ status: location.status, error: gate.code }, gate.status)
  }

  const { data: claimed, error: claimError } = await admin.rpc(
    'try_claim_location_moderation',
    { p_location_id: locationId },
  )
  if (claimError) return json({ error: 'moderation_claim_failed' }, 502)
  if (claimed !== true) {
    return json({ status: 'pending', error: 'moderation_in_progress' }, 409)
  }

  const recordFailure = async (errorCode: string) => {
    const { error } = await admin.rpc('record_location_moderation_result', {
      p_location_id: locationId,
      p_decision: null,
      p_confidence: null,
      p_reason_codes: [],
      p_short_reason: null,
      p_provider: 'configured_provider',
      p_model: model.trim(),
      p_attempt_status: 'error',
      p_error_code: errorCode,
    })
    if (error) throw error
  }

  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 12_000)
    let providerResponse: Response
    try {
      providerResponse = await fetch(providerUrl, {
        method: 'POST',
        signal: controller.signal,
        headers: { 'content-type': 'application/json', authorization: `Bearer ${providerKey}` },
        body: JSON.stringify(buildOpenAIRequest(location, model)),
      })
    } finally {
      clearTimeout(timeoutId)
    }
    if (!providerResponse.ok) {
      await recordFailure('provider_failure')
      return json({ status: 'pending', error: 'provider_failure' }, 502)
    }

    let providerPayload: unknown
    try {
      providerPayload = await providerResponse.json()
    } catch {
      await recordFailure('malformed_json')
      return json({ status: 'pending', error: 'malformed_json' }, 502)
    }

    let result
    try {
      result = parseOpenAIResponse(providerPayload)
    } catch (error) {
      const code = error instanceof Error ? error.message : 'invalid_schema'
      await recordFailure(code)
      return json({ status: 'pending', error: code }, 422)
    }

    const { data: status, error: moderationError } = await admin.rpc('record_location_moderation_result', {
      p_location_id: locationId,
      p_decision: result.decision,
      p_confidence: result.confidence,
      p_reason_codes: result.reason_codes,
      p_short_reason: result.short_reason,
      p_provider: 'configured_provider',
      p_model: model.trim(),
      p_attempt_status: 'succeeded',
      p_error_code: null,
    })
    if (moderationError) return json({ status: 'pending', error: 'database_transition_failed' }, 502)
    return json({ status, decision: result.decision })
  } catch (error) {
    const code = classifyProviderError(error)
    try {
      await recordFailure(code)
    } catch {
      return json({ status: 'pending', error: 'audit_write_failed' }, 500)
    }
    return json({ status: 'pending', error: code }, code === 'timeout' ? 504 : 500)
  }
})
