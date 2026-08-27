begin;

create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create index if not exists follows_following_idx
  on public.follows(following_id, created_at desc);

alter table public.follows enable row level security;

create policy follows_authenticated_read on public.follows
  for select to authenticated using (true);
create policy follows_create_self on public.follows
  for insert to authenticated
  with check (follower_id = auth.uid() and follower_id <> following_id);
create policy follows_delete_self on public.follows
  for delete to authenticated using (follower_id = auth.uid());

alter table public.locations
  add column if not exists is_public boolean not null default true;

drop policy if exists locations_social_read on public.locations;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute $policy$
      create policy locations_social_read on public.locations
      for select to authenticated using (is_public or user_id = auth.uid())
    $policy$;
  else
    execute $policy$
      create policy locations_social_read on public.locations
      for select to authenticated using (is_public or owner_id = auth.uid())
    $policy$;
  end if;
end;
$$;

create or replace function public.notify_user_about_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare follower_name text;
begin
  select coalesce(nullif(p.display_name, ''), p.username, 'Мандрівник')
    into follower_name from public.profiles p where p.id = new.follower_id;
  insert into public.notifications(user_id, title, message)
  values (
    new.following_id,
    'Новий підписник',
    left(coalesce(follower_name, 'Мандрівник'), 100) ||
      ' підписався на ваш профіль.'
  );
  return new;
end;
$$;

drop trigger if exists follows_notify_user on public.follows;
create trigger follows_notify_user
  after insert on public.follows
  for each row execute function public.notify_user_about_follow();

commit;
