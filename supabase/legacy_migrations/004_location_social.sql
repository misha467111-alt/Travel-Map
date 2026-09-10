begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
set local search_path = public, extensions, pg_catalog;

do $types$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'social_content_status'
  ) then
    create type public.social_content_status as enum (
      'pending', 'visible', 'hidden', 'deleted'
    );
  end if;
end
$types$;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9_-]{1,49}$'),
  name text not null check (char_length(btrim(name)) between 2 and 80),
  icon text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.categories add column if not exists is_active boolean default true;
alter table public.categories add column if not exists created_at timestamptz default now();
alter table public.categories add column if not exists updated_at timestamptz default now();
update public.categories set is_active = true where is_active is null;
update public.categories set created_at = now() where created_at is null;
update public.categories set updated_at = created_at where updated_at is null;
alter table public.categories alter column is_active set not null;
alter table public.categories alter column created_at set not null;
alter table public.categories alter column updated_at set not null;

create table if not exists public.location_categories (
  location_id uuid not null references public.locations(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  added_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (location_id, category_id)
);

alter table public.location_categories add column if not exists added_by uuid;
alter table public.location_categories add column if not exists created_at timestamptz default now();
update public.location_categories lc
set added_by = l.owner_id
from public.locations l
where l.id = lc.location_id and lc.added_by is null;
update public.location_categories set created_at = now() where created_at is null;
alter table public.location_categories alter column added_by set not null;
alter table public.location_categories alter column created_at set not null;

do $location_categories_constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.location_categories'::regclass
      and conname = 'location_categories_added_by_fkey'
  ) then
    alter table public.location_categories
      add constraint location_categories_added_by_fkey
      foreign key (added_by) references public.profiles(id) on delete cascade
      not valid;
  end if;
end
$location_categories_constraints$;

create table if not exists public.location_photos (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique
    check (char_length(storage_path) between 3 and 1024),
  caption text not null default '' check (char_length(caption) <= 500),
  sort_order smallint not null default 0 check (sort_order between 0 and 1000),
  status public.social_content_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9_-]{1,49}$'),
  name text not null check (char_length(btrim(name)) between 2 and 50),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.location_tags (
  location_id uuid not null references public.locations(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  added_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (location_id, tag_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  rating smallint check (rating between 1 and 5),
  status public.social_content_status not null default 'visible',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comments_parent_not_self_check check (parent_id is null or parent_id <> id)
);

create index if not exists location_categories_category_idx
  on public.location_categories (category_id, location_id);
create index if not exists location_photos_location_idx
  on public.location_photos (location_id, status, sort_order, created_at);
create index if not exists location_tags_tag_idx
  on public.location_tags (tag_id, location_id);
create index if not exists comments_location_created_idx
  on public.comments (location_id, created_at desc);
create index if not exists comments_parent_idx
  on public.comments (parent_id) where parent_id is not null;
create index if not exists comments_author_idx
  on public.comments (author_id, created_at desc);

create or replace function public.can_view_location(target_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.locations l
    where l.id = target_location_id
      and (
        l.owner_id = auth.uid()
        or (l.status = 'approved' and l.visibility in ('public', 'unlisted'))
      )
  )
$$;

create or replace function public.owns_location(target_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.locations l
    where l.id = target_location_id and l.owner_id = auth.uid()
  )
$$;

create or replace function public.protect_location_social_row()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor_column text := tg_argv[0];
  actor_id uuid;
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' then
      new := jsonb_populate_record(new, jsonb_build_object(actor_column, auth.uid()));
    end if;
    new.created_at := coalesce(new.created_at, now());
  else
    actor_id := (to_jsonb(old) ->> actor_column)::uuid;
    if current_user = 'authenticated' and (
      (to_jsonb(new) ->> actor_column)::uuid is distinct from actor_id
      or new.created_at is distinct from old.created_at
      or new.id is distinct from old.id
    ) then
      raise exception 'authorship and creation fields are server-managed'
        using errcode = '42501';
    end if;
  end if;

  new.updated_at := now();
  return new;
end
$$;

create or replace function public.set_location_social_join_author()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' then
    new := jsonb_populate_record(
      new,
      jsonb_build_object(tg_argv[0], auth.uid())
    );
  end if;
  new.created_at := coalesce(new.created_at, now());
  return new;
end
$$;

create or replace function public.protect_photo_moderation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' then
    if tg_op = 'INSERT' then
      new.status := 'pending';
    elsif new.status is distinct from old.status then
      raise exception 'photo status is server-managed' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;

create or replace function public.protect_comment_moderation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' then
    if tg_op = 'INSERT' then
      new.status := 'visible';
    elsif new.status is distinct from old.status then
      raise exception 'comment status is server-managed' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists location_photos_protect_row on public.location_photos;
create trigger location_photos_protect_row
before insert or update on public.location_photos
for each row execute function public.protect_location_social_row('uploader_id');
drop trigger if exists location_photos_protect_status on public.location_photos;
create trigger location_photos_protect_status
before insert or update on public.location_photos
for each row execute function public.protect_photo_moderation();

drop trigger if exists tags_protect_row on public.tags;
create trigger tags_protect_row
before insert or update on public.tags
for each row execute function public.protect_location_social_row('created_by');

drop trigger if exists location_categories_set_author on public.location_categories;
create trigger location_categories_set_author
before insert on public.location_categories
for each row execute function public.set_location_social_join_author('added_by');

drop trigger if exists location_tags_set_author on public.location_tags;
create trigger location_tags_set_author
before insert on public.location_tags
for each row execute function public.set_location_social_join_author('added_by');

drop trigger if exists comments_protect_row on public.comments;
create trigger comments_protect_row
before insert or update on public.comments
for each row execute function public.protect_location_social_row('author_id');
drop trigger if exists comments_protect_status on public.comments;
create trigger comments_protect_status
before insert or update on public.comments
for each row execute function public.protect_comment_moderation();

alter table public.categories enable row level security;
alter table public.location_categories enable row level security;
alter table public.location_photos enable row level security;
alter table public.tags enable row level security;
alter table public.location_tags enable row level security;
alter table public.comments enable row level security;

do $drop_policies$
declare
  table_name text;
  policy_record record;
begin
  foreach table_name in array array[
    'categories', 'location_categories', 'location_photos',
    'tags', 'location_tags', 'comments'
  ] loop
    for policy_record in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = table_name
    loop
      execute format('drop policy if exists %I on public.%I',
        policy_record.policyname, table_name);
    end loop;
  end loop;
end
$drop_policies$;

create policy categories_select_active on public.categories
for select to authenticated using (is_active);

create policy location_categories_select_visible on public.location_categories
for select to authenticated using (public.can_view_location(location_id));
create policy location_categories_insert_owner on public.location_categories
for insert to authenticated with check (
  added_by = (select auth.uid()) and public.owns_location(location_id)
);
create policy location_categories_delete_owner on public.location_categories
for delete to authenticated using (public.owns_location(location_id));

create policy location_photos_select_visible on public.location_photos
for select to authenticated using (
  uploader_id = (select auth.uid())
  or (status = 'visible' and public.can_view_location(location_id))
);
create policy location_photos_insert_owner on public.location_photos
for insert to authenticated with check (
  uploader_id = (select auth.uid()) and public.owns_location(location_id)
  and status = 'pending'
);
create policy location_photos_update_own on public.location_photos
for update to authenticated
using (uploader_id = (select auth.uid()))
with check (uploader_id = (select auth.uid()));
create policy location_photos_delete_own on public.location_photos
for delete to authenticated using (uploader_id = (select auth.uid()));

create policy tags_select on public.tags
for select to authenticated using (true);
create policy tags_insert_self on public.tags
for insert to authenticated with check (created_by = (select auth.uid()));
create policy tags_update_self on public.tags
for update to authenticated using (created_by = (select auth.uid()))
with check (created_by = (select auth.uid()));
create policy tags_delete_self on public.tags
for delete to authenticated using (created_by = (select auth.uid()));

create policy location_tags_select_visible on public.location_tags
for select to authenticated using (public.can_view_location(location_id));
create policy location_tags_insert_owner on public.location_tags
for insert to authenticated with check (
  added_by = (select auth.uid()) and public.owns_location(location_id)
);
create policy location_tags_delete_owner on public.location_tags
for delete to authenticated using (public.owns_location(location_id));

create policy comments_select_visible on public.comments
for select to authenticated using (
  author_id = (select auth.uid())
  or (status = 'visible' and public.can_view_location(location_id))
);
create policy comments_insert_self on public.comments
for insert to authenticated with check (
  author_id = (select auth.uid())
  and status = 'visible'
  and public.can_view_location(location_id)
);
create policy comments_update_self on public.comments
for update to authenticated using (
  author_id = (select auth.uid()) and status = 'visible'
)
with check (author_id = (select auth.uid()) and status = 'visible');
create policy comments_delete_self on public.comments
for delete to authenticated using (author_id = (select auth.uid()));

revoke all on table public.categories from anon, authenticated;
revoke all on table public.location_categories from anon, authenticated;
revoke all on table public.location_photos from anon, authenticated;
revoke all on table public.tags from anon, authenticated;
revoke all on table public.location_tags from anon, authenticated;
revoke all on table public.comments from anon, authenticated;

grant select on public.categories to authenticated;
grant select on public.location_categories to authenticated;
grant insert (location_id, category_id) on public.location_categories to authenticated;
grant delete on public.location_categories to authenticated;

grant select on public.location_photos to authenticated;
grant insert (location_id, storage_path, caption, sort_order) on public.location_photos to authenticated;
grant update (caption, sort_order) on public.location_photos to authenticated;
grant delete on public.location_photos to authenticated;

grant select on public.tags to authenticated;
grant insert (slug, name) on public.tags to authenticated;
grant update (slug, name) on public.tags to authenticated;
grant delete on public.tags to authenticated;

grant select on public.location_tags to authenticated;
grant insert (location_id, tag_id) on public.location_tags to authenticated;
grant delete on public.location_tags to authenticated;

grant select on public.comments to authenticated;
grant insert (location_id, parent_id, body, rating) on public.comments to authenticated;
grant update (body, rating) on public.comments to authenticated;
grant delete on public.comments to authenticated;

revoke all on function public.can_view_location(uuid) from public;
revoke all on function public.owns_location(uuid) from public;
revoke all on function public.protect_location_social_row() from public;
revoke all on function public.set_location_social_join_author() from public;
revoke all on function public.protect_photo_moderation() from public;
revoke all on function public.protect_comment_moderation() from public;
grant execute on function public.can_view_location(uuid) to authenticated;
grant execute on function public.owns_location(uuid) to authenticated;

commit;
