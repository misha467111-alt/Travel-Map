const fs = require('fs');
const { Client } = require('pg');

function envFile(path) {
  const out = {};
  for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([^#][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (match) out[match[1]] = match[2].trim().replace(/^['"]|['"]$/g, '');
  }
  return out;
}

async function main() {
  const audit = envFile('.env.audit');
  const pooler = fs.readFileSync('supabase/.temp/pooler-url', 'utf8').trim();
  const url = new URL(pooler);
  url.password = audit.SUPABASE_DB_PASSWORD;
  const db = new Client({ connectionString: url.toString(), ssl: { rejectUnauthorized: false } });
  const sql = fs.readFileSync(
    'supabase/migrations/202608270011_security_advisor_hardening.sql',
    'utf8',
  );
  await db.connect();
  await db.query('begin');
  try {
    await db.query(sql);
    const state = (await db.query(`
      select c.relname,c.relrowsecurity,
             has_table_privilege('anon',c.oid,'SELECT') anon_select,
             has_table_privilege('anon',c.oid,'INSERT') anon_insert,
             has_table_privilege('anon',c.oid,'UPDATE') anon_update,
             has_table_privilege('anon',c.oid,'DELETE') anon_delete,
             has_table_privilege('authenticated',c.oid,'SELECT') auth_select,
             has_table_privilege('authenticated',c.oid,'INSERT') auth_insert,
             has_table_privilege('authenticated',c.oid,'UPDATE') auth_update,
             has_table_privilege('authenticated',c.oid,'DELETE') auth_delete
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public'
         and c.relname=any(array['routes','invite_codes','spatial_ref_sys'])
       order by c.relname`)).rows;
    const policies = (await db.query(`
      select tablename,policyname,roles,cmd,qual
        from pg_policies
       where schemaname='public'
         and tablename=any(array['routes','invite_codes','spatial_ref_sys'])
       order by tablename,policyname`)).rows;
    const postgis = (await db.query(`
      select public.st_astext(public.st_transform(
               public.st_setsrid(public.st_makepoint(30.5234,50.4501),4326),3857
             )) transformed,
             public.st_dwithin(
               public.st_setsrid(public.st_makepoint(30.5234,50.4501),4326)::public.geography,
               public.st_setsrid(public.st_makepoint(30.5235,50.4502),4326)::public.geography,
               100
             ) dwithin,
             public.st_distance(
               public.st_setsrid(public.st_makepoint(30.5234,50.4501),4326)::public.geography,
               public.st_setsrid(public.st_makepoint(30.5235,50.4502),4326)::public.geography
             ) distance_m`)).rows[0];
    const spatialCount = (await db.query('select count(*) count from public.spatial_ref_sys')).rows[0].count;
    const expected = {
      routes: { clientSelect: false, clientWrite: false },
      invite_codes: { clientSelect: false, clientWrite: false },
    };
    for (const row of state) {
      const want = expected[row.relname];
      if (!want) continue;
      if (!row.relrowsecurity) throw new Error(`${row.relname}: RLS not enabled`);
      if (row.anon_select !== want.clientSelect || row.auth_select !== want.clientSelect) {
        throw new Error(`${row.relname}: unexpected SELECT privilege`);
      }
      if (row.anon_insert || row.anon_update || row.anon_delete ||
          row.auth_insert || row.auth_update || row.auth_delete) {
        throw new Error(`${row.relname}: client write privilege remains`);
      }
    }
    if (!postgis.transformed || postgis.dwithin !== true || Number(postgis.distance_m) <= 0) {
      throw new Error('PostGIS regression assertion failed');
    }
    if (Number(spatialCount) < 8000) throw new Error('spatial_ref_sys rows changed');
    process.stdout.write(JSON.stringify({ validation: 'PASS', state, policies, postgis, spatialCount }, null, 2));
  } finally {
    await db.query('rollback');
    await db.end();
  }
}

main().catch((error) => {
  process.stderr.write(`VALIDATION_FATAL=${error.message}\n`);
  process.exitCode = 1;
});
