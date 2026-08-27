const { Client } = require('pg');
const fs = require('fs');

async function main() {
  const client = new Client({
    connectionString: process.env.SUPABASE_DB_URL,
    ssl: { rejectUnauthorized: false },
    statement_timeout: 30000,
    query_timeout: 30000,
  });
  await client.connect();
  const queries = {
    server: `select current_database() database, current_user db_user, version() version`,
    migration_history: `select version, name, statements from supabase_migrations.schema_migrations order by version`,
    tables: `select table_schema, table_name from information_schema.tables where table_schema in ('public','storage') and table_type='BASE TABLE' order by 1,2`,
    columns: `select table_schema, table_name, ordinal_position, column_name, data_type, udt_name, is_nullable, column_default from information_schema.columns where table_schema in ('public','storage') order by 1,2,3`,
    constraints: `select n.nspname schema_name, c.relname table_name, con.conname, con.contype, pg_get_constraintdef(con.oid, true) definition from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage') order by 1,2,3`,
    indexes: `select schemaname, tablename, indexname, indexdef from pg_indexes where schemaname in ('public','storage') order by 1,2,3`,
    triggers: `select n.nspname schema_name, c.relname table_name, t.tgname, pg_get_triggerdef(t.oid, true) definition from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname in ('public','storage') order by 1,2,3`,
    functions: `select n.nspname schema_name, p.proname, pg_get_function_identity_arguments(p.oid) identity_args, pg_get_function_result(p.oid) result_type, p.prosecdef security_definer, p.proconfig settings, pg_get_userbyid(p.proowner) owner, pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' order by 2,3`,
    policies: `select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check from pg_policies where schemaname in ('public','storage') order by 1,2,3`,
    rls: `select n.nspname schema_name, c.relname table_name, c.relrowsecurity rls_enabled, c.relforcerowsecurity rls_forced from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname in ('public','storage') order by 1,2`,
    function_grants: `select routine_schema, routine_name, specific_name, grantee, privilege_type from information_schema.routine_privileges where routine_schema='public' order by 2,3,4`,
    table_grants: `select table_schema, table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) privileges from information_schema.role_table_grants where table_schema in ('public','storage') group by 1,2,3 order by 1,2,3`,
    buckets: `select id, name, public, file_size_limit, allowed_mime_types from storage.buckets order by id`,
  };
  const out = {};
  for (const [name, sql] of Object.entries(queries)) {
    try { out[name] = (await client.query(sql)).rows; }
    catch (error) { out[name] = { error: { code: error.code, message: error.message } }; }
  }
  const json = JSON.stringify(out);
  if (process.env.AUDIT_OUTPUT_PATH) {
    fs.writeFileSync(process.env.AUDIT_OUTPUT_PATH, json);
    console.log('INVENTORY_WRITTEN');
  } else {
    console.log(json);
  }
  await client.end();
}

main().catch((error) => {
  console.error(JSON.stringify({ fatal: { code: error.code, message: error.message } }));
  process.exitCode = 1;
});
