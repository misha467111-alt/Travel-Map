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
  const rows = (await db.query(
    `select id, title, author_id, points from public.routes where title = $1`,
    ['Маршрут 1.9'],
  )).rows;
  await db.end();
  console.log(JSON.stringify(rows.map((route) => ({
    id: route.id,
    title: route.title,
    author_matches_profile: route.author_id === 'ede85904-cfc8-4f5e-844a-6b9018ff747e',
    point_count: Array.isArray(route.points) ? route.points.length : null,
    points: route.points,
  })), null, 2));
}

main().catch((error) => {
  console.error(`ROUTE_PROBE_FATAL=${error.message}`);
  process.exitCode = 1;
});
