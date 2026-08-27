begin;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null default '',
  avatar_url text,
  xp integer not null default 0,
  level text not null default 'Новачок',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- These ALTER statements also make this migration safe for an older profiles
-- table that is already present in a deployed project.
alter table public.profiles add column if not exists user_id uuid;
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists name text;
alter table public.profiles add column if not exists display_name text not null default '';
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists xp integer not null default 0;
alter table public.profiles add column if not exists level text not null default 'Новачок';
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- PostgreSQL does not allow ALTER COLUMN TYPE while an RLS policy depends on
-- that column. Remove every legacy profiles policy before normalizing the
-- identity types. The canonical policies are recreated near the end of this
-- same transaction, so the table is never exposed without RLS protection.
do $drop_legacy_profile_policies$
declare
  policy_record record;
begin
  for policy_record in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
  loop
    execute format(
      'drop policy if exists %I on public.profiles',
      policy_record.policyname
    );
  end loop;
end
$drop_legacy_profile_policies$;

-- Older revisions used `text` for one or both identity columns. Normalize
-- their physical types before creating indexes, foreign keys, or comparing
-- them. Invalid legacy `user_id` values become NULL and are repaired from id
-- by the backfill immediately below.
do $identity_types$
declare
  id_type regtype;
  user_id_type regtype;
  invalid_id_count bigint;
begin
  select a.atttypid::regtype
  into id_type
  from pg_attribute a
  where a.attrelid = 'public.profiles'::regclass
    and a.attname = 'id'
    and a.attnum > 0
    and not a.attisdropped;

  select a.atttypid::regtype
  into user_id_type
  from pg_attribute a
  where a.attrelid = 'public.profiles'::regclass
    and a.attname = 'user_id'
    and a.attnum > 0
    and not a.attisdropped;

  if id_type is distinct from 'uuid'::regtype then
    select count(*)
    into invalid_id_count
    from public.profiles
    where id is null
       or id::text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    if invalid_id_count > 0 then
      raise exception
        'Cannot convert profiles.id to uuid: % invalid value(s)',
        invalid_id_count
        using errcode = '22023';
    end if;

    alter table public.profiles
      alter column id type uuid using id::text::uuid;
  end if;

  if user_id_type is distinct from 'uuid'::regtype then
    alter table public.profiles
      alter column user_id drop default;

    alter table public.profiles
      alter column user_id type uuid
      using case
        when user_id is not null
         and user_id::text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then user_id::text::uuid
        else null
      end;
  end if;
end
$identity_types$;

-- `user_id` is retained for compatibility with the legacy Flutter schema.
-- Both identity columns always refer to the same auth.users row.
update public.profiles
set user_id = id::text::uuid
where user_id::text is distinct from id::text;

update public.profiles
set username = 'explorer_' || substr(replace(id::text, '-', ''), 1, 12)
where username is null or btrim(username) = '';

-- `name` is a required legacy column. Keep it synchronized at creation time
-- while new clients use `display_name` as the canonical public label.
update public.profiles
set name = left(coalesce(
  nullif(btrim(display_name), ''),
  nullif(btrim(username), ''),
  'Дослідник'
), 80)
where name is null or btrim(name) = '';

alter table public.profiles alter column username set not null;
alter table public.profiles alter column name set default 'Дослідник';
alter table public.profiles alter column name set not null;
alter table public.profiles alter column user_id set not null;
alter table public.profiles alter column xp set default 0;
alter table public.profiles alter column xp set not null;
alter table public.profiles alter column level set default 'Новачок';
alter table public.profiles alter column level set not null;

do $constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_username_length_check'
  ) then
    alter table public.profiles
      add constraint profiles_username_length_check
      check (char_length(username) between 3 and 30) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_xp_nonnegative_check'
  ) then
    alter table public.profiles
      add constraint profiles_xp_nonnegative_check check (xp >= 0) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_identity_columns_match_check'
  ) then
    alter table public.profiles
      add constraint profiles_identity_columns_match_check
      check (user_id = id) not valid;
  end if;
end
$constraints$;

create unique index if not exists profiles_username_key
  on public.profiles (username);

create unique index if not exists profiles_user_id_key
  on public.profiles (user_id);

do $constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_user_id_fkey'
  ) then
    alter table public.profiles
      add constraint profiles_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade
      not valid;
  end if;
end
$constraints$;

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  locale text not null default 'uk' check (char_length(locale) between 2 and 16),
  theme text not null default 'system' check (theme in ('system', 'light', 'dark')),
  distance_unit text not null default 'metric'
    check (distance_unit in ('metric', 'imperial')),
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.profile_level_for_xp(points integer)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when points >= 500 then 'Мандрівник'
    when points >= 100 then 'Дослідник'
    else 'Новачок'
  end
$$;

create or replace function public.set_profile_server_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is null then
    raise exception 'profile id is required';
  end if;

  -- Prevent either client or server code from separating the profile from its
  -- Auth identity. This also supports the legacy `user_id` column.
  new.user_id := new.id;

  if tg_op = 'UPDATE'
     and current_user in ('anon', 'authenticated')
     and (
       new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.xp is distinct from old.xp
       or new.level is distinct from old.level
     ) then
    raise exception 'identity, xp and level are server-managed fields'
      using errcode = '42501';
  end if;

  new.xp := greatest(coalesce(new.xp, 0), 0);
  new.level := public.profile_level_for_xp(new.xp);
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists profiles_server_fields_before_write on public.profiles;
create trigger profiles_server_fields_before_write
before insert or update on public.profiles
for each row execute function public.set_profile_server_fields();

create or replace function public.set_user_settings_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists user_settings_before_update on public.user_settings;
create trigger user_settings_before_update
before update on public.user_settings
for each row execute function public.set_user_settings_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate_username text;
  candidate_display_name text;
begin
  candidate_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data ->> 'username', ''),
    '[^a-zA-Z0-9_]+', '', 'g'
  ));

  if char_length(candidate_username) < 3 then
    candidate_username := 'explorer';
  end if;

  candidate_username := left(candidate_username, 17)
    || '_' || substr(replace(new.id::text, '-', ''), 1, 12);

  candidate_display_name := left(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Дослідник'
  ), 80);

  insert into public.profiles (
    id,
    user_id,
    name,
    username,
    display_name,
    avatar_url
  )
  values (
    new.id,
    new.id,
    candidate_display_name,
    candidate_username,
    candidate_display_name,
    nullif(btrim(new.raw_user_meta_data ->> 'avatar_url'), '')
  )
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Backfill identity rows created before this migration.
insert into public.profiles (
  id,
  user_id,
  name,
  username,
  display_name,
  avatar_url
)
select
  u.id,
  u.id,
  left(coalesce(
    nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'Дослідник'
  ), 80),
  'explorer_' || substr(replace(u.id::text, '-', ''), 1, 12),
  left(coalesce(
    nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
    split_part(coalesce(u.email, ''), '@', 1),
    'Дослідник'
  ), 80),
  nullif(btrim(u.raw_user_meta_data ->> 'avatar_url'), '')
from auth.users u
on conflict (id) do nothing;

insert into public.user_settings (user_id)
select id from auth.users
on conflict (user_id) do nothing;

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;

-- Remove the legacy broad update policy from earlier project revisions.
drop policy if exists profiles_update_self on public.profiles;

drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated
on public.profiles for select
to authenticated
using (true);

drop policy if exists profiles_update_public_fields_self on public.profiles;
create policy profiles_update_public_fields_self
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists user_settings_select_self on public.user_settings;
create policy user_settings_select_self
on public.user_settings for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists user_settings_insert_self on public.user_settings;
create policy user_settings_insert_self
on public.user_settings for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists user_settings_update_self on public.user_settings;
create policy user_settings_update_self
on public.user_settings for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists user_settings_delete_self on public.user_settings;
create policy user_settings_delete_self
on public.user_settings for delete
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (username, display_name, avatar_url) on public.profiles to authenticated;

revoke all on table public.user_settings from anon, authenticated;
grant select, insert, update, delete on public.user_settings to authenticated;

revoke all on function public.profile_level_for_xp(integer) from public;
revoke all on function public.set_profile_server_fields() from public;
revoke all on function public.set_user_settings_updated_at() from public;
revoke all on function public.handle_new_auth_user() from public;

commit;
