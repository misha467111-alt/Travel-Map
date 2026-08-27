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
  const url = new URL(fs.readFileSync('supabase/.temp/pooler-url', 'utf8').trim());
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
    await db.query('commit');
    process.stdout.write('APPLY=PASS migration=202608270011\n');
  } catch (error) {
    await db.query('rollback');
    throw error;
  } finally {
    await db.end();
  }
}

main().catch((error) => {
  process.stderr.write(`APPLY_FATAL=${error.message}\n`);
  process.exitCode = 1;
});
