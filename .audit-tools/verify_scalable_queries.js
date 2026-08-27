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
  const app = envFile('.env');
  let connectionString = process.env.TRAVEL_AUDIT_DB_URL || audit.SUPABASE_DB_URL;
  if (!process.env.TRAVEL_AUDIT_DB_URL && fs.existsSync('supabase/.temp/pooler-url')) {
    const pooler = fs.readFileSync('supabase/.temp/pooler-url', 'utf8').trim();
    const url = new URL(pooler);
    url.password = audit.SUPABASE_DB_PASSWORD;
    connectionString = url.toString();
  }
  const client = new Client({ connectionString, ssl: { rejectUnauthorized: false } });
  await client.connect();

  const migrationTables = await client.query(
    `select table_schema, table_name
       from information_schema.tables
      where table_name = 'schema_migrations'`,
  );
  let migration = { rows: [] };
  if (migrationTables.rows.some((row) => row.table_schema === 'supabase_migrations')) {
    migration = await client.query(
      `select version, name from supabase_migrations.schema_migrations where version = $1`,
      ['202608270010'],
    );
  }
  const functions = await client.query(
    `select p.proname,
            pg_get_function_identity_arguments(p.oid) as args,
            pg_get_function_result(p.oid) as result,
            p.prosecdef as security_definer
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = any($1)
      order by p.proname`,
    [[
      'travel_locations_in_bounds',
      'travel_discover_locations',
      'travel_nearby_locations',
    ]],
  );
  await client.end();

  const base = (audit.SUPABASE_URL || app.SUPABASE_URL).replace(/\/$/, '');
  const token = audit.SUPABASE_SECRET_KEY;
  const headers = {
    apikey: token,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
  const calls = {
    travel_locations_in_bounds: {
      p_min_lng: 30, p_min_lat: 40, p_max_lng: 31, p_max_lat: 41, p_limit: 1,
    },
    travel_discover_locations: { p_limit: 1 },
    travel_nearby_locations: {
      p_latitude: 50.45, p_longitude: 30.52, p_radius_m: 1000, p_limit: 1,
    },
  };
  const smoke = {};
  for (const [name, body] of Object.entries(calls)) {
    const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
      method: 'POST', headers, body: JSON.stringify(body),
    });
    const payload = await response.json().catch(() => null);
    smoke[name] = {
      status: response.status,
      ok: response.ok,
      rows: Array.isArray(payload) ? payload.length : null,
      errorCode: response.ok ? null : payload?.code,
    };
  }

  process.stdout.write(JSON.stringify({
    migrationTable: migrationTables.rows,
    migration: migration.rows,
    functions: functions.rows,
    smoke,
  }, null, 2));
}

main().catch((error) => {
  process.stderr.write(`VERIFY_FATAL=${error.name}: ${error.message}\n`);
  process.exitCode = 1;
});
