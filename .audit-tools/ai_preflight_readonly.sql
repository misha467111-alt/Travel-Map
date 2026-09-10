select json_build_object(
  'location_columns', (
    select json_agg(x order by x.ordinal_position) from (
      select ordinal_position,column_name,data_type,udt_name,is_nullable,column_default
      from information_schema.columns
      where table_schema='public' and table_name='locations'
    ) x
  ),
  'profile_columns', (
    select json_agg(x order by x.ordinal_position) from (
      select ordinal_position,column_name,data_type,udt_name,is_nullable,column_default
      from information_schema.columns
      where table_schema='public' and table_name='profiles'
    ) x
  ),
  'foreign_keys', (
    select json_agg(x order by x.constraint_name) from (
      select tc.constraint_name,tc.table_name,kcu.column_name,
             ccu.table_schema foreign_table_schema,ccu.table_name foreign_table_name,
             ccu.column_name foreign_column_name
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on tc.constraint_name=kcu.constraint_name and tc.constraint_schema=kcu.constraint_schema
      join information_schema.constraint_column_usage ccu
        on ccu.constraint_name=tc.constraint_name and ccu.constraint_schema=tc.constraint_schema
      where tc.constraint_schema='public' and tc.constraint_type='FOREIGN KEY'
        and tc.table_name in ('locations','profiles')
    ) x
  ),
  'primary_and_unique', (
    select json_agg(x order by x.constraint_name) from (
      select tc.constraint_name,tc.constraint_type,tc.table_name,
             string_agg(kcu.column_name,',' order by kcu.ordinal_position) columns
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on tc.constraint_name=kcu.constraint_name and tc.constraint_schema=kcu.constraint_schema
      where tc.constraint_schema='public' and tc.table_name in ('locations','profiles')
        and tc.constraint_type in ('PRIMARY KEY','UNIQUE')
      group by tc.constraint_name,tc.constraint_type,tc.table_name
    ) x
  ),
  'location_status_labels', (
    select json_agg(e.enumlabel order by e.enumsortorder)
    from pg_type t join pg_enum e on e.enumtypid=t.oid
    join pg_namespace n on n.oid=t.typnamespace
    where n.nspname='public' and t.typname='location_status'
  ),
  'triggers', (
    select json_agg(x order by x.table_name,x.trigger_name) from (
      select c.relname table_name,t.tgname trigger_name,
             pg_get_triggerdef(t.oid) trigger_definition,
             pg_get_functiondef(t.tgfoid) function_definition
      from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname in ('locations','profiles') and not t.tgisinternal
    ) x
  ),
  'relation_checks', (
    select row_to_json(x) from (
      select
        (select count(*) from public.profiles where id<>user_id) profile_id_user_id_mismatches,
        (select count(*) from public.locations l left join public.profiles p on p.id=l.owner_id where p.id is null) owners_missing_profile_by_id,
        (select count(*) from public.locations l left join public.profiles p on p.user_id=l.owner_id where p.user_id is null) owners_missing_profile_by_user_id,
        (select count(*) from public.locations) location_count
    ) x
  )
) as preflight;
