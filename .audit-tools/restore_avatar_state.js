const fs = require('fs');
const { Client } = require('pg');

function envFile(path) {
  const values = {};
  for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([^#][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (match) values[match[1]] = match[2].trim().replace(/^['"]|['"]$/g, '');
  }
  return values;
}

async function main() {
  const env = { ...envFile('.env'), ...envFile('.env.audit') };
  const connection = new URL(fs.readFileSync('supabase/.temp/pooler-url', 'utf8').trim());
  connection.password = env.SUPABASE_DB_PASSWORD;
  const db = new Client({ connectionString: connection.toString(), ssl: { rejectUnauthorized: false } });
  await db.connect();
  const profile = (await db.query(
    `select id, username from public.profiles where username = $1 limit 1`,
    ['papaetoty'],
  )).rows[0];
  if (!profile) throw new Error('Target profile not found');

  await db.query('begin');
  try {
    const update = await db.query(
      `update public.profiles set avatar_url = null where id = $1 returning username, avatar_url`,
      [profile.id],
    );
    if (update.rowCount !== 1 || update.rows[0].username !== 'papaetoty') {
      throw new Error('Unexpected profile update scope');
    }
    await db.query('commit');
  } catch (error) {
    await db.query('rollback');
    throw error;
  } finally {
    await db.end();
  }

  const base = env.SUPABASE_URL.replace(/\/$/, '');
  const adminHeaders = {
    apikey: env.SUPABASE_SECRET_KEY,
    Authorization: `Bearer ${env.SUPABASE_SECRET_KEY}`,
    'Content-Type': 'application/json',
  };
  const read = await fetch(`${base}/auth/v1/admin/users/${profile.id}`, { headers: adminHeaders });
  const user = await read.json();
  if (!read.ok) throw new Error(`Auth user read HTTP ${read.status}`);
  const write = await fetch(`${base}/auth/v1/admin/users/${profile.id}`, {
    method: 'PUT',
    headers: adminHeaders,
    body: JSON.stringify({ user_metadata: { ...(user.user_metadata || {}), avatar_url: null } }),
  });
  if (!write.ok) throw new Error(`Auth metadata restore HTTP ${write.status}`);
  console.log(JSON.stringify({
    profile: profile.username,
    db_avatar_restored_to_null: true,
    auth_avatar_restored_to_null: true,
  }, null, 2));
}

main().catch((error) => {
  console.error(`AVATAR_RESTORE_FATAL=${error.message}`);
  process.exitCode = 1;
});
