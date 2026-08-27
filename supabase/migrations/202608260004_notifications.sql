begin;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  message text not null check (char_length(message) between 1 and 500),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);
create index if not exists notifications_user_unread_idx
  on public.notifications(user_id, created_at desc) where not is_read;

alter table public.notifications enable row level security;

drop policy if exists notifications_read_own on public.notifications;
create policy notifications_read_own on public.notifications
  for select to authenticated using (user_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public.protect_notification_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id
     or new.user_id <> old.user_id
     or new.title <> old.title
     or new.message <> old.message
     or new.created_at <> old.created_at then
    raise exception 'only notification read status can be updated';
  end if;
  if old.is_read and not new.is_read then
    raise exception 'a read notification cannot be marked unread';
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_protect_fields on public.notifications;
create trigger notifications_protect_fields
  before update on public.notifications
  for each row execute function public.protect_notification_fields();

create or replace function public.notify_location_owner_about_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner uuid;
  location_title text;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute 'select user_id, title from public.locations where id = $1'
      into location_owner, location_title using new.location_id;
  else
    execute 'select owner_id, name from public.locations where id = $1'
      into location_owner, location_title using new.location_id;
  end if;

  if location_owner is null or location_owner = new.author_id then
    return new;
  end if;

  insert into public.notifications(user_id, title, message)
  values (
    location_owner,
    'Новий відгук',
    'До локації «' || left(coalesce(location_title, 'Без назви'), 100) ||
      '» додано новий коментар.'
  );
  return new;
end;
$$;

drop trigger if exists reviews_notify_location_owner on public.reviews;
create trigger reviews_notify_location_owner
  after insert on public.reviews
  for each row execute function public.notify_location_owner_about_review();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;

commit;
