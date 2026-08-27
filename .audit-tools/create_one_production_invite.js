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

async function json(response) {
  return response.json().catch(() => ({}));
}

async function main() {
  const audit = envFile('.env.audit');
  const app = envFile('.env');
  const base = (audit.SUPABASE_URL || app.SUPABASE_URL).replace(/\/$/, '');
  const anon = app.SUPABASE_ANON_KEY || app.SUPABASE_PUBLISHABLE_KEY || audit.SUPABASE_PUBLISHABLE_KEY;
  const secret = audit.SUPABASE_SECRET_KEY || app.SUPABASE_SECRET_KEY;
  if (!base || !anon || !secret) throw new Error('required Supabase configuration is missing');

  const stamp = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
  const email = `manual-invite-owner-${stamp}@example.invalid`;
  const password = `Audit-${crypto.randomBytes(30).toString('base64url')}!9a`;
  const adminHeaders = {
    apikey: secret,
    Authorization: `Bearer ${secret}`,
    'Content-Type': 'application/json',
    'User-Agent': 'travel-production-manual-invite/1.0',
  };

  const createUser = await fetch(`${base}/auth/v1/admin/users`, {
    method: 'POST', headers: adminHeaders,
    body: JSON.stringify({
      email, password, email_confirm: true,
      user_metadata: { username: `Manual Invite Audit ${stamp}`, purpose: 'manual_android_invite_test' },
    }),
  });
  const owner = await json(createUser);
  if (!createUser.ok || !owner.id) throw new Error(`audit owner creation failed (HTTP ${createUser.status})`);

  const prepare = await fetch(`${base}/rest/v1/profiles?id=eq.${encodeURIComponent(owner.id)}`, {
    method: 'PATCH',
    headers: { ...adminHeaders, Prefer: 'return=representation' },
    body: JSON.stringify({ invite_redeemed: true, invite_balance: 1 }),
  });
  const prepared = await json(prepare);
  if (!prepare.ok || !Array.isArray(prepared) || prepared.length !== 1) {
    throw new Error(`audit owner preparation failed (HTTP ${prepare.status})`);
  }

  const login = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const session = await json(login);
  if (!login.ok || !session.access_token) throw new Error(`audit owner login failed (HTTP ${login.status})`);

  // The only invite creation: authenticated production RPC, exactly once.
  const issue = await fetch(`${base}/rest/v1/rpc/create_invite`, {
    method: 'POST',
    headers: {
      apikey: anon, Authorization: `Bearer ${session.access_token}`,
      'Content-Type': 'application/json', Accept: 'application/json',
    },
    body: '{}',
  });
  const code = await json(issue);
  if (!issue.ok || typeof code !== 'string') throw new Error(`create_invite RPC failed (HTTP ${issue.status})`);

  const verify = await fetch(`${base}/rest/v1/invites?select=code,uses,max_uses&code=eq.${encodeURIComponent(code)}`, {
    headers: adminHeaders,
  });
  const rows = await json(verify);
  const active = verify.ok && Array.isArray(rows) && rows.length === 1 && rows[0].uses === 0 && rows[0].max_uses > 0;
  if (!active) throw new Error('invite verification failed after creation');

  console.log(`TEST_INVITE_CODE=${code}`);
  console.log('ACTIVE_UNUSED=YES');
}

main().catch((error) => {
  console.error(`FAILED=${error.message}`);
  process.exitCode = 1;
});
