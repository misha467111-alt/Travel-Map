begin;

create table if not exists public.friendships (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id_1 uuid not null references auth.users(id) on delete cascade,
  user_id_2 uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  check (user_id_1 <> user_id_2)
);

create unique index if not exists friendships_unique_pair_idx
  on public.friendships (least(user_id_1, user_id_2), greatest(user_id_1, user_id_2));
create index if not exists friendships_user_1_idx on public.friendships(user_id_1, status);
create index if not exists friendships_user_2_idx on public.friendships(user_id_2, status);

alter table public.friendships enable row level security;

drop policy if exists friendships_participants_read on public.friendships;
create policy friendships_participants_read
on public.friendships for select to authenticated
using (auth.uid() = user_id_1 or auth.uid() = user_id_2);

drop policy if exists friendships_send on public.friendships;
create policy friendships_send
on public.friendships for insert to authenticated
with check (
  auth.uid() = user_id_1
  and user_id_1 <> user_id_2
  and status = 'pending'
);

drop policy if exists friendships_participants_update on public.friendships;
create policy friendships_participants_update
on public.friendships for update to authenticated
using (auth.uid() = user_id_1 or auth.uid() = user_id_2)
with check (
  (auth.uid() = user_id_1 or auth.uid() = user_id_2)
  and status in ('pending', 'accepted')
);

drop policy if exists profiles_social_read on public.profiles;
create policy profiles_social_read
on public.profiles for select to authenticated
using (true);

do $$
begin
  execute 'drop policy if exists locations_social_read on public.locations';

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute $policy$
      create policy locations_social_read
      on public.locations for select to authenticated
      using (
        user_id = auth.uid()
        or exists (
          select 1 from public.friendships friendship
          where friendship.status = 'accepted'
            and (
              (friendship.user_id_1 = auth.uid() and friendship.user_id_2 = locations.user_id)
              or
              (friendship.user_id_2 = auth.uid() and friendship.user_id_1 = locations.user_id)
            )
        )
      )
    $policy$;
  else
    execute $policy$
      create policy locations_social_read
      on public.locations for select to authenticated
      using (
        owner_id = auth.uid()
        or exists (
          select 1 from public.friendships friendship
          where friendship.status = 'accepted'
            and (
              (friendship.user_id_1 = auth.uid() and friendship.user_id_2 = locations.owner_id)
              or
              (friendship.user_id_2 = auth.uid() and friendship.user_id_1 = locations.owner_id)
            )
        )
      )
    $policy$;
  end if;
end;
$$;

commit;
