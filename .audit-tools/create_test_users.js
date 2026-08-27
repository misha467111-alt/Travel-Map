const fs = require('fs');
const crypto = require('crypto');

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
  const secret = audit.SUPABASE_SECRET_KEY;
  const headers = {
    apikey: secret, Authorization: `Bearer ${secret}`,
    'Content-Type': 'application/json', 'User-Agent': 'travel-production-audit/1.0',
  };
  const run = `audit-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
  const created = [];
  for (const label of ['a', 'b']) {
    const email = `${run}-${label}@example.invalid`;
    const password = `Audit-${crypto.randomBytes(24).toString('base64url')}!9a`;
    const response = await fetch(`${base}/auth/v1/admin/users`, {
      method: 'POST', headers,
      body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { username: `Audit ${label.toUpperCase()} ${run}` } }),
    });
    const body = await response.json().catch(() => ({}));
    console.log(`CREATE_USER_${label.toUpperCase()}=${response.ok ? 'PASS' : 'FAIL'} HTTP_${response.status} code=${body.code || body.error_code || ''} message=${body.message || body.msg || ''}`);
    if (response.ok) created.push({ id: body.id, email, password });
  }
  fs.writeFileSync('.audit-tools/test_users.json', JSON.stringify({ run, users: created }));
}

main().catch((error) => {
  console.error(`CREATE_FATAL=${error.name}`);
  process.exitCode = 1;
});
