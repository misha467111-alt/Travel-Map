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
  const pooler = fs.readFileSync('supabase/.temp/pooler-url', 'utf8').trim();
  const url = new URL(pooler);
  url.password = audit.SUPABASE_DB_PASSWORD;
  const db = new Client({ connectionString: url.toString(), ssl: { rejectUnauthorized: false } });
  await db.connect();
  const names = ['routes', 'invite_codes', 'spatial_ref_sys'];
  const result = {};
  result.objects = (await db.query(`
    select c.relname, c.relkind, pg_get_userbyid(c.relowner) owner,
           c.relrowsecurity rls, c.relforcerowsecurity force_rls,
           obj_description(c.oid) comment
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=any($1)
     order by c.relname`, [names])).rows;
  result.columns = (await db.query(`
    select table_name,column_name,data_type,udt_name,is_nullable,column_default
      from information_schema.columns
     where table_schema='public' and table_name=any($1)
     order by table_name,ordinal_position`, [names])).rows;
  result.constraints = (await db.query(`
    select c.conrelid::regclass::text table_name,c.conname,c.contype,
           pg_get_constraintdef(c.oid) definition
      from pg_constraint c
     where c.conrelid=any(array['public.routes'::regclass,'public.invite_codes'::regclass,'public.spatial_ref_sys'::regclass])
     order by 1,2`)).rows;
  result.indexes = (await db.query(`
    select tablename,indexname,indexdef from pg_indexes
     where schemaname='public' and tablename=any($1) order by 1,2`, [names])).rows;
  result.policies = (await db.query(`
    select tablename,policyname,permissive,roles,cmd,qual,with_check
      from pg_policies where schemaname='public' and tablename=any($1)
     order by 1,2`, [names])).rows;
  result.grants = (await db.query(`
    select table_name,grantee,privilege_type
      from information_schema.role_table_grants
     where table_schema='public' and table_name=any($1)
       and grantee=any(array['anon','authenticated','service_role','PUBLIC','postgres'])
     order by 1,2,3`, [names])).rows;
  result.effective = (await db.query(`
    select object_name,role_name,privilege,
           has_table_privilege(role_name,format('public.%I',object_name),privilege) allowed
      from unnest($1::text[]) object_name
      cross join unnest(array['anon','authenticated','service_role']) role_name
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) privilege
     order by 1,2,3`, [names])).rows;
  result.acl = (await db.query(`
    select c.relname,coalesce(r.rolname,'PUBLIC') grantee,x.privilege_type,x.is_grantable
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
      left join pg_roles r on r.oid=x.grantee
     where n.nspname='public' and c.relname=any($1)
     order by 1,2,3`, [names])).rows;
  result.triggers = (await db.query(`
    select event_object_table,trigger_name,event_manipulation,action_statement
      from information_schema.triggers
     where event_object_schema='public' and event_object_table=any($1)
     order by 1,2`, [names])).rows;
  result.dependencies = (await db.query(`
    select source::regclass::text source, dependent_class, dependent_identity, deptype
      from (
        select d.refobjid source,
               d.classid::regclass::text dependent_class,
               pg_describe_object(d.classid,d.objid,d.objsubid) dependent_identity,
               d.deptype
          from pg_depend d
         where d.refobjid=any(array['public.routes'::regclass,'public.invite_codes'::regclass,'public.spatial_ref_sys'::regclass])
      ) x order by 1,2,3`)).rows;
  result.functionReferences = (await db.query(`
    select n.nspname schema,p.proname,
           pg_get_function_identity_arguments(p.oid) args,
           p.prosecdef security_definer,
           pg_get_functiondef(p.oid) definition
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.prokind in ('f','p') and (
       pg_get_functiondef(p.oid) ilike '%public.routes%' or
       pg_get_functiondef(p.oid) ilike '%public.invite_codes%' or
       pg_get_functiondef(p.oid) ilike '%spatial_ref_sys%'
     ) order by 1,2`)).rows;
  result.extensions = (await db.query(`
    select e.extname,n.nspname schema,pg_get_userbyid(e.extowner) owner,
           e.extversion,
           exists(select 1 from pg_depend d where d.refclassid='pg_extension'::regclass
             and d.refobjid=e.oid and d.objid='public.spatial_ref_sys'::regclass) owns_spatial_ref_sys
      from pg_extension e join pg_namespace n on n.oid=e.extnamespace
     where e.extname='postgis'`)).rows;
  result.counts = (await db.query(`
    select (select count(*) from public.routes) routes,
           (select count(*) from public.invite_codes) invite_codes,
           (select count(*) from public.spatial_ref_sys) spatial_ref_sys`)).rows;
  await db.end();

  const base = (audit.SUPABASE_URL || app.SUPABASE_URL).replace(/\/$/, '');
  const anonKey = app.SUPABASE_ANON_KEY || app.SUPABASE_KEY;
  result.postgrestAnon = {};
  for (const name of names) {
    const response = await fetch(`${base}/rest/v1/${name}?select=*&limit=1`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}` },
    });
    const body = await response.json().catch(() => null);
    result.postgrestAnon[name] = {
      status: response.status,
      rows: Array.isArray(body) ? body.length : null,
      code: response.ok ? null : body?.code,
    };
  }
  process.stdout.write(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  process.stderr.write(`FORENSICS_FATAL=${error.name}: ${error.message}\n`);
  process.exitCode = 1;
});
