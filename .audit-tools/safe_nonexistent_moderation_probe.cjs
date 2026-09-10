const fs = require('fs');
const {execFileSync} = require('child_process');
const {randomUUID, createHash} = require('crypto');
const {Client} = require('pg');
let stage = 'initialization';
let requests = 0;
function envFile(path) {
  const out = {};
  for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
  return out;
}
function decode(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|quot|apos|lt|gt|amp);/gi, (_, x) => {
    if (x.startsWith('#x')) return String.fromCodePoint(parseInt(x.slice(2),16));
    if (x.startsWith('#')) return String.fromCodePoint(Number(x.slice(1)));
    return {quot:'"',apos:"'",lt:'<',gt:'>',amp:'&'}[x];
  });
}
const hash = x => createHash('sha256').update(JSON.stringify(x)).digest('hex');
async function main() {
  const cfg = {...envFile('.env'), ...envFile('.env.audit')};
  stage = 'session_read';
  const xml = execFileSync('C:/Users/papae/AppData/Local/Android/sdk/platform-tools/adb.exe',
    ['-s','R58M34G0J7W','shell','run-as','com.example.travel_map_final','cat','shared_prefs/FlutterSharedPreferences.xml'],
    {encoding:'utf8',stdio:['ignore','pipe','pipe']});
  const entries = [...xml.matchAll(/<string name="([^"]+)">([\s\S]*?)<\/string>/g)];
  const entry = entries.find(m => /supabase|auth.*token/i.test(m[1]));
  const session = entry ? JSON.parse(decode(entry[2])) : null;
  if (!session?.access_token || session.expires_at * 1000 <= Date.now()) {
    console.log('AUTH SESSION AVAILABLE: NO'); return;
  }
  stage = 'auth_validation';
  const base = cfg.SUPABASE_URL.replace(/\/$/, '');
  const headers = {apikey:cfg.SUPABASE_ANON_KEY,Authorization:`Bearer ${session.access_token}`};
  const auth = await fetch(`${base}/auth/v1/user`, {headers,signal:AbortSignal.timeout(20000)});
  const user = await auth.json();
  if (!auth.ok || !user.id || user.id !== session.user?.id) {
    console.log(JSON.stringify({authenticated_session:false,auth_http_status:auth.status,function_requests:requests})); return;
  }
  console.log('AUTH SESSION AVAILABLE: YES');
  stage = 'database_connect';
  const dbUrl = new URL(fs.readFileSync('supabase/.temp/pooler-url','utf8').trim());
  dbUrl.password = cfg.SUPABASE_DB_PASSWORD;
  const db = new Client({connectionString:dbUrl.toString(),ssl:{rejectUnauthorized:false},connectionTimeoutMillis:20000});
  await db.connect();
  async function snapshot(id) {
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    try {
      const tables = {};
      for (const table of ['locations','profiles','invites','invite_redemptions','location_moderation_audits']) {
        tables[table] = (await db.query(`SELECT to_jsonb(t) AS row FROM public.${table} t ORDER BY to_jsonb(t)::text`)).rows.map(r=>r.row);
      }
      const exists = (await db.query('SELECT EXISTS(SELECT 1 FROM public.locations WHERE id=$1) AS found',[id])).rows[0].found;
      await db.query('COMMIT');
      return {tables,exists};
    } catch(e) { await db.query('ROLLBACK'); throw e; }
  }
  try {
    stage = 'before_snapshot';
    const id = randomUUID();
    const before = await snapshot(id);
    if (before.exists || before.tables.locations.length !== 50 || before.tables.location_moderation_audits.length !== 0) {
      console.log(JSON.stringify({stopped:'precondition_mismatch',uuid_exists:before.exists,locations:before.tables.locations.length,audit_count:before.tables.location_moderation_audits.length,function_requests:requests})); return;
    }
    console.log(JSON.stringify({uuid:id,nonexistent_verified:true,locations_before:50,audit_before:0}));
    stage = 'single_function_request';
    requests++;
    const response = await fetch(`${base}/functions/v1/moderate-content`, {
      method:'POST',headers:{...headers,'Content-Type':'application/json'},
      body:JSON.stringify({location_id:id}),redirect:'error',signal:AbortSignal.timeout(25000)
    });
    const body = await response.json().catch(()=>null);
    const code = typeof body?.error === 'string' && /^[a-z_]{1,80}$/.test(body.error) ? body.error :
      typeof body?.code === 'number' ? body.code : 'unrecognized_response';
    console.log(JSON.stringify({http_status:response.status,error_code:code,safe_response:body?.error === 'location_not_found' ? {error:'location_not_found'} : {code},function_requests:requests}));
    stage = 'after_snapshot';
    const after = await snapshot(id);
    const same = name => hash(before.tables[name]) === hash(after.tables[name]);
    const statuses = s => s.tables.locations.map(r=>({id:r.id,status:r.status})).sort((a,b)=>a.id.localeCompare(b.id));
    console.log(JSON.stringify({handler_reached:response.status===404 && code==='location_not_found',nonexistent_uuid_handled_safely:response.status===404 && code==='location_not_found' && !after.exists,locations_after:after.tables.locations.length,locations_unchanged:same('locations'),statuses_unchanged:hash(statuses(before))===hash(statuses(after)),profiles_including_xp_unchanged:same('profiles'),invites_unchanged:same('invites')&&same('invite_redemptions'),audit_count:after.tables.location_moderation_audits.length,audits_unchanged:same('location_moderation_audits'),function_requests:requests}));
  } finally { await db.end(); }
}
main().catch(()=>{ console.log(JSON.stringify({failed_stage:stage,function_requests:requests,details:'suppressed_to_protect_secrets'}));process.exitCode=1; });
