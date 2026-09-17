import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const sql = readFileSync(
  new URL(
    '../../migrations/202609160002_activity_events_foundation.sql',
    import.meta.url,
  ),
  'utf8',
)

// ---------------------------------------------------------------------------
// General safety net -- found as a REAL live-runtime defect during Phase
// 2C: Postgres/Supabase's `supabase_admin` role grants `authenticated`
// full (arwdDxtm) privileges on every newly CREATE TABLE'd relation by
// default (this is not documented anywhere in this repo's own migrations
// -- it only became visible by checking pg_class.relacl on an actually
// running database, which is exactly why this phase exists). Every
// `revoke all on table ...` statement for a table this migration creates
// MUST include `authenticated` explicitly, or the client keeps full
// access underneath an "additive" SELECT-only grant that looks correct
// in isolation. This test scans every such revoke line generically, so it
// would catch the same mistake on a future table too, not just these 3.
// ---------------------------------------------------------------------------

test('every table-level revoke for a table this migration CREATEs includes '
  + 'authenticated explicitly (Postgres/Supabase default-grants authenticated '
  + 'full rights on new tables; omitting it here is a real security defect, '
  + 'not just style)', () => {
  const createdTables = ['activity_event_types', 'activity_reward_rules', 'activity_events']
  const revokeLines = sql
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.toLowerCase().startsWith('revoke all on table'))
  assert.equal(revokeLines.length, createdTables.length)
  for (const table of createdTables) {
    const line = revokeLines.find((l) => l.includes(`public.${table}`))
    assert.ok(line, `expected a revoke-all line for ${table}`)
    assert.match(line, /from public, anon, authenticated;/)
  }
})

// ---------------------------------------------------------------------------
// activity_event_types
// ---------------------------------------------------------------------------

test('activity_event_types has the exact 8 approved keys, no more, no fewer', () => {
  const expected = [
    'LOCATION_APPROVED',
    'LOCATION_VISITED',
    'LOCATION_CREATED',
    'ROUTE_PLANNED_CREATED',
    'ROUTE_RECORDED_COMPLETED',
    'ROUTE_FOLLOWED_COMPLETED',
    'QUEST_COMPLETED',
    'TREASURE_FOUND',
  ]
  for (const key of expected) {
    assert.match(sql, new RegExp(`'${key}',`))
  }
  const insertBlock = sql.split('insert into public.activity_event_types')[1].split(';')[0]
  const matches = insertBlock.match(/'[A-Z_]+',/g) ?? []
  assert.equal(matches.length, expected.length)
})

test('activity_event_types is read-only to clients: no insert/update/delete grant', () => {
  assert.match(
    sql,
    /revoke all on table public\.activity_event_types from public, anon, authenticated;/,
  )
  assert.match(
    sql,
    /grant select on table public\.activity_event_types to authenticated, service_role;/,
  )
  // Exact grant-line audit (not just presence/absence of keywords): this
  // is the check that would have caught the real Phase 2C defect, where
  // the revoke omitted `authenticated`, leaving it with Postgres/Supabase's
  // default broad table privileges on every newly created table intact
  // underneath an *additive* explicit SELECT grant.
  const grantLines = sql
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.toLowerCase().startsWith('grant') && line.includes('activity_event_types'))
  assert.deepEqual(grantLines, [
    'grant select on table public.activity_event_types to authenticated, service_role;',
  ])
})

// ---------------------------------------------------------------------------
// activity_reward_rules
// ---------------------------------------------------------------------------

test('LOCATION_APPROVED and LOCATION_VISITED are the only active rewards, '
  + 'with the exact approved XP amounts', () => {
  const insertBlock = sql
    .split('insert into public.activity_reward_rules')[1]
    .split(';')[0]
  assert.match(insertBlock, /\('LOCATION_APPROVED', 10, true\)/)
  assert.match(insertBlock, /\('LOCATION_VISITED', 20, true\)/)
})

test('every reserved event type is inactive with zero XP', () => {
  const insertBlock = sql
    .split('insert into public.activity_reward_rules')[1]
    .split(';')[0]
  for (const key of [
    'LOCATION_CREATED',
    'ROUTE_PLANNED_CREATED',
    'ROUTE_RECORDED_COMPLETED',
    'ROUTE_FOLLOWED_COMPLETED',
    'QUEST_COMPLETED',
    'TREASURE_FOUND',
  ]) {
    assert.match(insertBlock, new RegExp(`\\('${key}', 0, false\\)`))
  }
})

test('reward rules cannot go negative and are not client-writable', () => {
  assert.match(sql, /constraint activity_reward_rules_xp_amount_nonneg_check check \(xp_amount >= 0\)/)
  assert.match(
    sql,
    /revoke all on table public\.activity_reward_rules from public, anon, authenticated;/,
  )
  assert.match(
    sql,
    /grant select on table public\.activity_reward_rules to authenticated, service_role;/,
  )
  const grantLines = sql
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.toLowerCase().startsWith('grant') && line.includes('activity_reward_rules'))
  assert.deepEqual(grantLines, [
    'grant select on table public.activity_reward_rules to authenticated, service_role;',
  ])
})

// ---------------------------------------------------------------------------
// activity_events
// ---------------------------------------------------------------------------

test('activity_events has the approved columns including the FK chain and '
  + 'the append-only-relevant defaults', () => {
  const createBlock = sql.split('create table public.activity_events (')[1].split(
    'create unique index activity_events_user_type_source_uidx',
  )[0]
  assert.match(createBlock, /id uuid primary key default gen_random_uuid\(\)/)
  assert.match(createBlock, /user_id uuid not null references public\.profiles\(id\) on delete cascade/)
  assert.match(createBlock, /event_type text not null references public\.activity_event_types\(key\)/)
  assert.match(createBlock, /subject_type text not null/)
  assert.match(createBlock, /subject_id uuid not null/)
  assert.match(createBlock, /source_id uuid not null/)
  assert.match(createBlock, /metadata jsonb not null default '\{\}'::jsonb/)
  assert.match(createBlock, /xp_awarded integer not null default 0/)
  assert.match(createBlock, /occurred_at timestamp with time zone not null/)
  assert.match(createBlock, /created_at timestamp with time zone not null default now\(\)/)
})

test('the idempotency backstop is a real UNIQUE index on (user_id, event_type, source_id)', () => {
  assert.match(
    sql,
    /create unique index activity_events_user_type_source_uidx\s*\n\s*on public\.activity_events \(user_id, event_type, source_id\);/,
  )
})

test('activity_events RLS: authenticated can only SELECT its own rows', () => {
  assert.match(sql, /alter table public\.activity_events enable row level security;/)
  assert.match(
    sql,
    /create policy activity_events_read_own on public\.activity_events\s*\n\s*as permissive for select to authenticated\s*\n\s*using \(user_id = \(select auth\.uid\(\)\)\);/,
  )
})

test('activity_events grants: no client-facing role can INSERT/UPDATE/DELETE, '
  + 'only SELECT for authenticated, SELECT+INSERT for service_role', () => {
  assert.match(sql, /revoke all on table public\.activity_events from public, anon, authenticated;/)
  assert.match(sql, /grant select on table public\.activity_events to authenticated;/)
  assert.match(
    sql,
    /grant select, insert on table public\.activity_events to service_role;/,
  )
  // Scan only actual `grant ...;` statement lines (comments/prose, which
  // freely use words like "update"/"delete" in explanatory text, are
  // excluded by construction here instead of relying on a greedy regex
  // over the whole file).
  const grantLines = sql
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.toLowerCase().startsWith('grant') && line.includes('activity_events'))
  assert.deepEqual(grantLines, [
    'grant select on table public.activity_events to authenticated;',
    'grant select, insert on table public.activity_events to service_role;',
  ])
})

// ---------------------------------------------------------------------------
// _record_activity_event
// ---------------------------------------------------------------------------

test('_record_activity_event is SECURITY DEFINER with a controlled search_path', () => {
  const body = sql.split('create function public._record_activity_event(')[1]
  assert.match(body, /security definer/)
  assert.match(body, /set search_path = extensions, public, pg_catalog/)
})

test('_record_activity_event is revoked from PUBLIC/anon/authenticated -- not '
  + 'a public RPC', () => {
  assert.match(
    sql,
    /revoke all on function public\._record_activity_event\(\s*uuid, text, text, uuid, uuid, jsonb, timestamp with time zone\s*\) from public, anon, authenticated;/,
  )
})

test('_record_activity_event never awards XP on a conflict (duplicate) insert', () => {
  const body = sql.split('create function public._record_activity_event(')[1]
  assert.match(
    body,
    /on conflict \(user_id, event_type, source_id\) do nothing\s*\n\s*returning id into inserted_id;/,
  )
  assert.match(body, /if inserted_id is null then/)
  // The early-return-zero branch must come BEFORE the profiles update.
  const conflictBranch = body.split('if inserted_id is null then')[1].split('end if;')[0]
  assert.match(conflictBranch, /return query select null::uuid, 0;/)
  assert.doesNotMatch(conflictBranch, /update public\.profiles/)
})

test('the realized XP is computed from activity_reward_rules, never a '
  + 'client-supplied amount', () => {
  const body = sql.split('create function public._record_activity_event(')[1]
  assert.match(
    body,
    /select r\.xp_amount, r\.is_active into reward_amount, reward_active\s*\n\s*from public\.activity_reward_rules r/,
  )
  // The function signature has no xp/amount parameter at all.
  const signature = sql.split('create function public._record_activity_event(')[1].split(')')[0]
  assert.doesNotMatch(signature, /xp/i)
})

// ---------------------------------------------------------------------------
// create_check_in widening
// ---------------------------------------------------------------------------

test('create_check_in is widened in place (DROP + CREATE), not a second '
  + 'overload -- exactly one definition exists', () => {
  assert.match(
    sql,
    /drop function if exists public\.create_check_in\(\s*uuid, double precision, double precision, double precision\s*\);/,
  )
  const matches = sql.match(/create function public\.create_check_in\(/g) ?? []
  assert.equal(matches.length, 1)
})

test('create_check_in preserves the original 4 parameter names/order and '
  + 'adds p_request_id as the only new, optional, trailing parameter', () => {
  assert.match(
    sql,
    /create function public\.create_check_in\(\s*target_location_id uuid,\s*user_lat double precision,\s*user_lng double precision,\s*gps_accuracy_m double precision,\s*p_request_id uuid default null\s*\)/,
  )
})

test('check_ins.request_id is nullable and additive -- existing rows are '
  + 'untouched', () => {
  assert.match(
    sql,
    /alter table public\.check_ins add column if not exists request_id uuid;/,
  )
  // Not NOT NULL anywhere.
  assert.doesNotMatch(sql, /request_id uuid not null/)
})

test('check_ins request_id idempotency is scoped per-user via a partial '
  + 'unique index, mirroring locations_owner_request_id_uidx', () => {
  assert.match(
    sql,
    /create unique index if not exists check_ins_user_request_id_uidx\s*\n\s*on public\.check_ins using btree \(user_id, request_id\)\s*\n\s*where \(request_id is not null\);/,
  )
})

test('an exact request_id retry returns the ORIGINAL result and never '
  + 'reaches the cooldown check or a second insert', () => {
  const body = sql.split('create function public.create_check_in(')[1]
  const preCooldown = body.split('if recent_count > 0 then')[0]
  assert.match(preCooldown, /if p_request_id is not null then/)
  assert.match(preCooldown, /select id into existing_check_in_id/)
  assert.match(preCooldown, /return jsonb_build_object\('check_in_id', existing_check_in_id, 'xp_awarded', coalesce\(awarded, 0\)\);/)
})

test('a concurrent race on the same request_id is handled via unique_violation, '
  + 'not left to error out', () => {
  const body = sql.split('create function public.create_check_in(')[1]
  assert.match(body, /exception when unique_violation then/)
  assert.match(body, /if p_request_id is null then raise; end if;/)
})

test('create_check_in calls the shared event helper instead of writing XP inline', () => {
  const body = sql.split('create function public.create_check_in(')[1]
  assert.match(
    body,
    /select \* into event_row from public\._record_activity_event\(/,
  )
  assert.match(body, /p_event_type := 'LOCATION_VISITED'/)
  assert.match(body, /p_subject_type := 'location'/)
  assert.match(body, /p_subject_id := target_location_id/)
  assert.match(body, /p_source_id := check_in_id/)
  // No inline "update profiles set xp" left anywhere in this function body.
  const wholeFunction = body.split('$function$')[0]
  assert.doesNotMatch(wholeFunction, /update public\.profiles set xp/)
})

test('create_check_in grants match the pre-existing privilege model '
  + '(authenticated + service_role, never anon)', () => {
  assert.match(
    sql,
    /revoke all on function public\.create_check_in\(\s*uuid, double precision, double precision, double precision, uuid\s*\) from public, anon;/,
  )
  assert.match(
    sql,
    /grant execute on function public\.create_check_in\(\s*uuid, double precision, double precision, double precision, uuid\s*\) to authenticated, service_role;/,
  )
})

// ---------------------------------------------------------------------------
// record_location_moderation_result refactor
// ---------------------------------------------------------------------------

test('record_location_moderation_result keeps its exact original 9-parameter '
  + 'signature and location_status return type', () => {
  assert.match(
    sql,
    /create or replace function public\.record_location_moderation_result\(\s*p_location_id uuid,\s*p_decision text,\s*p_confidence double precision,\s*p_reason_codes text\[\],\s*p_short_reason text,\s*p_provider text,\s*p_model text,\s*p_attempt_status text,\s*p_error_code text default null\s*\)\s*returns public\.location_status/,
  )
})

test('the approval_rewarded_at guard is preserved verbatim as the domain-level guard', () => {
  const body = sql.split('create or replace function public.record_location_moderation_result')[1]
  assert.match(
    body,
    /if next_status='approved' and not reward_already_given then\s*\n\s*update public\.locations set status='approved', approval_rewarded_at=now\(\), moderation_started_at=null\s*\n\s*where id=p_location_id and approval_rewarded_at is null;\s*\n\s*if found then/,
  )
})

test('the inline XP update is replaced by the shared helper call, LOCATION_APPROVED, '
  + 'location subject/source both = p_location_id', () => {
  const body = sql.split('create or replace function public.record_location_moderation_result')[1]
  assert.match(body, /perform public\._record_activity_event\(/)
  assert.match(body, /p_event_type := 'LOCATION_APPROVED'/)
  assert.match(body, /p_subject_type := 'location'/)
  assert.match(body, /p_subject_id := p_location_id/)
  assert.match(body, /p_source_id := p_location_id/)
  const wholeFunction = body.split('$function$')[0]
  assert.doesNotMatch(wholeFunction, /update public\.profiles set xp/)
})

test('moderation state semantics (validation, audit insert, status transitions) '
  + 'are otherwise untouched', () => {
  const body = sql.split('create or replace function public.record_location_moderation_result')[1]
  assert.match(body, /raise exception 'location is not pending moderation' using errcode='55000';/)
  assert.match(body, /insert into public\.location_moderation_audits\(/)
  assert.match(body, /elsif next_status <> current_status then/)
})

// ---------------------------------------------------------------------------
// No historical reward replay / no XP-system redefinition
// ---------------------------------------------------------------------------

test('the migration never touches existing users\' xp/level/invite fields '
  + 'outside the two guarded reward paths', () => {
  // Strip `--` comment lines first -- this migration's own prose
  // deliberately quotes the OLD inline "update public.profiles set xp=..."
  // statements it replaced, which would otherwise false-positive-match here.
  const codeOnly = sql
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n')
  const allUpdatesToProfiles = codeOnly.match(/update public\.profiles set [^;]+;/g) ?? []
  for (const stmt of allUpdatesToProfiles) {
    assert.match(stmt, /xp = coalesce\(xp, 0\) \+ realized_xp/)
  }
  // Exactly one such statement exists in the whole file (inside the helper).
  assert.equal(allUpdatesToProfiles.length, 1)
})

test('the migration does not redefine the level/invite trigger chain', () => {
  assert.doesNotMatch(sql, /create (or replace )?function public\.profile_level_for_xp/)
  assert.doesNotMatch(sql, /create (or replace )?function public\.travel_level_tier/)
  assert.doesNotMatch(sql, /create (or replace )?function public\.set_profile_server_fields/)
  assert.doesNotMatch(sql, /create (or replace )?function public\.award_invite_for_level_unlock/)
})

test('there is no backfill INSERT into activity_events for historical rows '
  + '-- the only insert into that table is the one inside the runtime helper '
  + 'function, not a standalone seed/backfill statement', () => {
  const withoutHelperBody = sql.replace(
    /create function public\._record_activity_event\([\s\S]*?\$function\$\s*;/,
    '',
  )
  assert.doesNotMatch(withoutHelperBody, /insert into public\.activity_events/)
})
