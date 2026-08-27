const fs = require('fs');
const { Client } = require('pg');
function envFile(path) { const out={}; for(const line of fs.readFileSync(path,'utf8').split(/\r?\n/)){const m=line.match(/^\s*([^#][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);if(m)out[m[1]]=m[2].trim().replace(/^['"]|['"]$/g,'');} return out; }
async function main(){
 const e=envFile('.env.audit'), app=envFile('.env'); const u=new URL(fs.readFileSync('supabase/.temp/pooler-url','utf8').trim());u.password=e.SUPABASE_DB_PASSWORD;
 const db=new Client({connectionString:u.toString(),ssl:{rejectUnauthorized:false}}); await db.connect();
 const dbState=(await db.query(`select c.relname name,c.relrowsecurity rls,has_table_privilege('anon',c.oid,'select') anon_select,has_table_privilege('authenticated',c.oid,'select') auth_select,has_table_privilege('anon',c.oid,'insert') anon_insert,has_table_privilege('authenticated',c.oid,'insert') auth_insert from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('routes','invite_codes','spatial_ref_sys') order by 1`)).rows;
 const postgis=(await db.query(`select public.st_dwithin(public.st_setsrid(public.st_makepoint(30.5234,50.4501),4326)::public.geography,public.st_setsrid(public.st_makepoint(30.5235,50.4502),4326)::public.geography,100) dwithin,public.st_distance(public.st_setsrid(public.st_makepoint(30.5234,50.4501),4326)::public.geography,public.st_setsrid(public.st_makepoint(30.5235,50.4502),4326)::public.geography) distance_m,(select count(*) from public.spatial_ref_sys) spatial_count`)).rows[0]; await db.end();
 const base=app.SUPABASE_URL.replace(/\/$/,''); const key=app.SUPABASE_ANON_KEY; const rest={};
 for(const table of ['routes','invite_codes','spatial_ref_sys']){const h={apikey:key,Authorization:`Bearer ${key}`}; const read=await fetch(`${base}/rest/v1/${table}?select=*&limit=1`,{headers:h}); const write=await fetch(`${base}/rest/v1/${table}`,{method:'POST',headers:{...h,'Content-Type':'application/json','Prefer':'return=minimal'},body:'{}'}); rest[table]={read:read.status,write:write.status};}
 for(const [name,body] of Object.entries({travel_locations_in_bounds:{p_min_lng:30,p_min_lat:40,p_max_lng:31,p_max_lat:41,p_limit:1},travel_discover_locations:{p_limit:1},travel_nearby_locations:{p_latitude:50.45,p_longitude:30.52,p_radius_m:1000,p_limit:1}})){const r=await fetch(`${base}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body)});rest[name]={status:r.status,ok:r.ok};}
 console.log(JSON.stringify({dbState,postgis,rest},null,2));
}
main().catch(e=>{console.error(`POSTCHECK_FATAL=${e.message}`);process.exitCode=1});
