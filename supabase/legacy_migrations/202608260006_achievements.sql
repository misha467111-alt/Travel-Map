begin;

alter table public.profiles
  add column if not exists distance_traveled_km numeric not null default 0
  check (distance_traveled_km >= 0);

create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_key text not null check (achievement_key in (
    'first_location', 'ten_friends', 'photo_collector', 'explorer_100km'
  )),
  unlocked_at timestamptz not null default now(),
  unique (user_id, achievement_key)
);

create index if not exists user_achievements_user_idx
  on public.user_achievements(user_id, unlocked_at desc);

alter table public.user_achievements enable row level security;

create policy user_achievements_read_own on public.user_achievements
  for select to authenticated using (user_id = auth.uid());

create or replace function public.check_and_unlock_achievements()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  locations_count integer := 0;
  friends_count integer := 0;
  photos_count integer := 0;
  distance_km numeric := 0;
begin
  if uid is null then raise exception 'authentication required'; end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute 'select count(*) from public.locations where user_id = $1'
      into locations_count using uid;
    execute $query$
      select count(*) from public.locations
      where user_id = $1 and nullif(btrim(image_url), '') is not null
    $query$ into photos_count using uid;
  else
    execute 'select count(*) from public.locations where owner_id = $1'
      into locations_count using uid;
    execute $query$
      select count(*) from public.locations
      where owner_id = $1 and nullif(btrim(image_url), '') is not null
    $query$ into photos_count using uid;
  end if;

  select count(*) into friends_count from public.friendships
  where status = 'accepted' and (user_id_1 = uid or user_id_2 = uid);
  select distance_traveled_km into distance_km
    from public.profiles where id = uid;

  if locations_count >= 1 then
    insert into public.user_achievements(user_id, achievement_key)
    values (uid, 'first_location') on conflict do nothing;
  end if;
  if friends_count >= 10 then
    insert into public.user_achievements(user_id, achievement_key)
    values (uid, 'ten_friends') on conflict do nothing;
  end if;
  if photos_count >= 10 then
    insert into public.user_achievements(user_id, achievement_key)
    values (uid, 'photo_collector') on conflict do nothing;
  end if;
  if coalesce(distance_km, 0) >= 100 then
    insert into public.user_achievements(user_id, achievement_key)
    values (uid, 'explorer_100km') on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.check_and_unlock_achievements() from public;
grant execute on function public.check_and_unlock_achievements()
  to authenticated;

commit;
