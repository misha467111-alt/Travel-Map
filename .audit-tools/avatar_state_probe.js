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
    `select id, username, avatar_url from public.profiles where username = $1 limit 1`,
    ['papaetoty'],
  )).rows[0];
  const objects = profile
    ? (await db.query(
        `select name, metadata->>'size' as size, created_at
           from storage.objects
          where bucket_id = 'avatars' and name like $1
          order by created_at desc limit 5`,
        [`${profile.id}/%`],
      )).rows
    : [];
  let publicObject = null;
  if (profile?.avatar_url) {
    const response = await fetch(profile.avatar_url);
    publicObject = {
      status: response.status,
      content_type: response.headers.get('content-type'),
      content_length: response.headers.get('content-length'),
      cache_control: response.headers.get('cache-control'),
      bytes: (await response.arrayBuffer()).byteLength,
    };
  }
  await db.end();
  console.log(JSON.stringify({
    profile_found: Boolean(profile),
    username: profile?.username ?? null,
    avatar_url_present: Boolean(profile?.avatar_url),
    avatar_url_tail: profile?.avatar_url?.split('/').slice(-2).join('/') ?? null,
    objects,
    public_object: publicObject,
  }, null, 2));
}

main().catch((error) => {
  console.error(`AVATAR_PROBE_FATAL=${error.message}`);
  process.exitCode = 1;
});
