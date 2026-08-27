const fs = require('fs');

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
  const base = (audit.SUPABASE_URL || app.SUPABASE_URL).replace(/\/$/, '');
  const headers = {
    apikey: audit.SUPABASE_SECRET_KEY,
    Authorization: `Bearer ${audit.SUPABASE_SECRET_KEY}`,
    'User-Agent': 'travel-production-audit/1.0',
  };
  for (const [name, path] of Object.entries({
    Data_API: '/rest/v1/', Auth_API: '/auth/v1/settings', Storage_API: '/storage/v1/bucket',
  })) {
    const response = await fetch(base + path, { headers });
    let detail = '';
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      detail = ` code=${body.code || ''} message=${body.message || body.msg || ''}`;
    }
    console.log(`${name}=${response.ok ? 'PASS' : 'FAIL'} HTTP_${response.status}${detail}`);
  }
}

main().catch((error) => {
  console.error(`PROBE_FATAL=${error.name}`);
  process.exitCode = 1;
});
