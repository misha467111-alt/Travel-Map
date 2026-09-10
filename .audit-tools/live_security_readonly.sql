select table_name, string_agg(grantee, ',' order by grantee) as client_truncate_grantees
from information_schema.role_table_grants
where table_schema='public'
  and privilege_type='TRUNCATE'
  and grantee in ('PUBLIC','anon','authenticated')
group by table_name
order by table_name;

select tablename, rowsecurity
from pg_tables
where schemaname='public'
order by tablename;

select policyname, cmd, roles::text, qual, with_check
from pg_policies
where schemaname='public' and tablename='locations'
order by policyname;

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid='public.locations'::regclass and not tgisinternal;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema='public'
  and routine_name in ('record_location_moderation_result','create_location_with_xp')
  and grantee in ('PUBLIC','anon','authenticated','service_role')
order by routine_name,grantee;
