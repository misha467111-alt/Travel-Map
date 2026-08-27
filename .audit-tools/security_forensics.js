const fs = require('fs');
const { Client } = require('pg');
function envFile(path) { const out = {}; for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) { const m = line.match(/^\s*([^#][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/); if (m) out[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, ''); } return out; }
async function main() {
  const e = envFile('.env.audit'); const u = new URL(fs.readFileSync('supabase/.temp/pooler-url','utf8').trim()); u.password = e.SUPABASE_DB_PASSWORD;
  const c = new Client({connectionString:u.toString(), ssl:{rejectUnauthorized:false}}); await c.connect();
  const names = ['routes','invite_codes','spatial_ref_sys'];
  const q = async (sql, params=[]) => (await c.query(sql, params)).rows;
  const objects = await q(`select n.nspname as schema, c.relname as name, c.relkind, pg_get_userbyid(c.relowner) owner, c.relrowsecurity rls_enabled, c.relforcerowsecurity rls_forced, obj_description(c.oid) description from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=any($1)`, [names]);
  const columns = await q(`select table_name,column_name,data_type,udt_name,is_nullable,column_default from information_schema.columns where table_schema='public' and table_name=any($1) order by table_name,ordinal_position`, [names]);
  const constraints = await q(`select conrelid::regclass::text table_name, conname, contype, pg_get_constraintdef(oid) definition from pg_constraint where conrelid in (select oid from pg_class where relnamespace='public'::regnamespace and relname=any($1)) order by 1,2`, [names]);
  const indexes = await q(`select tablename,indexname,indexdef from pg_indexes where schemaname='public' and tablename=any($1) order by tablename,indexname`, [names]);
  const policies = await q(`select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies where schemaname='public' and tablename=any($1) order by tablename,policyname`, [names]);
  const grants = await q(`select table_name,grantee,string_agg(privilege_type,',' order by privilege_type) privileges from information_schema.role_table_grants where table_schema='public' and table_name=any($1) group by table_name,grantee order by table_name,grantee`, [names]);
  const exposure = await q(`select table_name, table_type from information_schema.tables where table_schema='public' and table_name=any($1)`, [names]);
  const refs = await q(`select dependent_ns.nspname||'.'||dependent.relname dependent, source_ns.nspname||'.'||source.relname source from pg_depend d join pg_class dependent on dependent.oid=d.objid join pg_namespace dependent_ns on dependent_ns.oid=dependent.relnamespace join pg_class source on source.oid=d.refobjid join pg_namespace source_ns on source_ns.oid=source.relnamespace where source_ns.nspname='public' and source.relname=any($1) order by 1,2`, [names]);
  const funcs = [];
  const ext = await q(`select e.extname,e.extversion,n.nspname schema,pg_get_userbyid(e.extowner) owner from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='postgis'`);
  await c.end(); console.log(JSON.stringify({objects,columns,constraints,indexes,policies,grants,exposure,refs,funcs,postgis_extension:ext},null,2));
}
main().catch(e=>{console.error(`FORENSIC_FATAL=${e.message}`);process.exitCode=1});
