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
  await db.connect();
  const membership = (await db.query(`
    select current_user,
           pg_has_role(current_user,'supabase_admin','MEMBER') member,
           pg_has_role(current_user,'supabase_admin','USAGE') usage,
           pg_has_role(current_user,'supabase_admin','SET') can_set`)).rows[0];
  let setRole = 'NOT_TRIED';
  await db.query('begin');
  try {
    await db.query('set local role supabase_admin');
    setRole = (await db.query('select current_user')).rows[0].current_user;
  } catch (error) {
    setRole = `DENIED:${error.code}`;
  } finally {
    await db.query('rollback');
  }
  await db.end();
  process.stdout.write(JSON.stringify({ membership, setRole }, null, 2));
}

main().catch((error) => {
  process.stderr.write(`ROLE_CHECK_FATAL=${error.message}\n`);
  process.exitCode = 1;
});
