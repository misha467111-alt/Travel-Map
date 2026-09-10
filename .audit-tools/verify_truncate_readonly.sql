with application_tables(table_name) as (values
  ('achievement_definitions'),('categories'),('check_ins'),('comments'),
  ('follows'),('friendships'),('invite_codes'),('invite_redemptions'),
  ('invites'),('location_categories'),('location_photos'),('location_tags'),
  ('locations'),('messages'),('notifications'),('profiles'),('reviews'),
  ('routes'),('tags'),('user_achievements'),('user_settings')
), client_roles(grantee) as (values ('PUBLIC'),('anon'),('authenticated'))
select t.table_name, r.grantee,
  exists (
    select 1 from information_schema.role_table_grants g
    where g.table_schema='public' and g.table_name=t.table_name
      and g.grantee=r.grantee and g.privilege_type='TRUNCATE'
  ) as has_truncate
from application_tables t cross join client_roles r
order by t.table_name, r.grantee;
