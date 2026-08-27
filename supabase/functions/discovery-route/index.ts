import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (request) => {
  const auth = request.headers.get('Authorization') ?? ''
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } })
  if (!(await client.auth.getUser()).data.user) return new Response('Unauthorized', { status: 401 })
  const { latitude, longitude, maxDistanceKm = 20, minutes = 120, transport = 'walking', mood = [] } = await request.json()
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || maxDistanceKm < 1 || maxDistanceKm > 200) return Response.json({ error: 'Invalid constraints' }, { status: 400 })
  const { data, error } = await client.rpc('nearby_discovery_candidates', { user_lat: latitude, user_lng: longitude, radius_m: maxDistanceKm * 1000, mood_filter: mood })
  if (error) return Response.json({ error: error.message }, { status: 400 })
  return Response.json({ transport, minutes, stops: (data ?? []).slice(0, Math.max(2, Math.min(8, Math.floor(minutes / 30)))) })
})
