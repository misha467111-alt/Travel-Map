import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (request) => {
  const token = request.headers.get('Authorization') ?? ''
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: token } } })
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new Response('Unauthorized', { status: 401 })
  const { kind, id, text = '', mediaUrl } = await request.json()
  if (!['location', 'post', 'media'].includes(kind) || !id) return Response.json({ error: 'Invalid payload' }, { status: 400 })
  const moderationUrl = Deno.env.get('MODERATION_API_URL')
  const moderationKey = Deno.env.get('MODERATION_API_KEY')
  if (!moderationUrl || !moderationKey) return Response.json({ error: 'Moderation is not configured' }, { status: 503 })
  const result = await fetch(moderationUrl, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${moderationKey}` }, body: JSON.stringify({ text, mediaUrl, checks: ['spam', 'abuse', 'nsfw', 'duplicate'] }) })
  if (!result.ok) return Response.json({ error: 'Moderation provider failed' }, { status: 502 })
  const verdict = await result.json()
  return Response.json({ approved: verdict.approved === true, labels: verdict.labels ?? [] })
})
