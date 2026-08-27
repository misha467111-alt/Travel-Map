const fs = require('fs');
const { Client } = require('pg');
function envFile(path) { const out = {}; for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) { const m = line.match(/^\s*([^#][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/); if (m) out[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, ''); } return out; }
async function main() {
  const e = envFile('.env.audit'); const u = new URL(fs.readFileSync('supabase/.temp/pooler-url','utf8').trim()); u.password = e.SUPABASE_DB_PASSWORD;
  const c = new Client({connectionString:u.toString(), ssl:{rejectUnauthorized:false}}); await c.connect();
  const sql = fs.readFileSync('supabase/migrations/202608270011_security_advisor_hardening.sql','utf8');
  await c.query('begin');
  try {
    await c.query(sql);
    const rows = await c.query(`select c.relname name,c.relrowsecurity rls_enabled,has_table_privilege('anon',c.oid,'select') anon_select,has_table_privilege('authenticated',c.oid,'select') auth_select,has_table_privilege('anon',c.oid,'insert') anon_insert,has_table_privilege('authenticated',c.oid,'insert') auth_insert from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('routes','invite_codes') order by c.relname`);
    const spatial = await c.query(`select c.relname name,c.relrowsecurity rls_enabled,pg_get_userbyid(c.relowner) owner,has_table_privilege('anon',c.oid,'select') anon_select,has_table_privilege('authenticated',c.oid,'select') auth_select from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='spatial_ref_sys'`);
    await c.query('rollback'); await c.end(); console.log(JSON.stringify({transaction:'PASS',post_sql:rows.rows,spatial_unchanged:spatial.rows},null,2));
  } catch (err) { await c.query('rollback'); await c.end(); throw err; }
}
main().catch(e=>{console.error(`VALIDATE_FATAL=${e.message}`);process.exitCode=1});
