begin;

-- This forward migration is the final authority after all legacy migrations.
-- It intentionally replaces policies instead of relying on permissive policy
-- composition, where any older policy could otherwise widen access.

alter table public.profiles enable row level security;
alter table public.locations enable row level security;
alter table public.comments enable row level security;
alter table public.location_photos enable row level security;
alter table public.check_ins enable row level security;
alter table public.follows enable row level security;
alter table public.notifications enable row level security;
alter table public.user_achievements enable row level security;

alter table public.profiles
  add column if not exists invite_redeemed boolean not null default false;
alter table public.profiles
  add column if not exists invited_by uuid references public.profiles(id);
alter table public.profiles
  add column if not exists invite_balance integer not null default 1
  check (invite_balance >= 0);
alter table public.profiles
  add column if not exists is_developer boolean not null default false;

-- Profiles that predate server-enforced invites were already admitted by the
-- legacy application. Do not lock them out during this migration.
update public.profiles set invite_redeemed = true
where invite_redeemed = false;

do $clear_policies$
declare
  target_table text;
  policy_record record;
begin
  foreach target_table in array array[
    'profiles', 'locations', 'comments', 'location_photos',
    'check_ins', 'follows', 'notifications', 'user_achievements'
  ] loop
    for policy_record in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = target_table
    loop
      execute format(
        'drop policy if exists %I on public.%I',
        policy_record.policyname,
        target_table
      );
    end loop;
  end loop;
end
$clear_policies$;

create policy profiles_select_authenticated on public.profiles
for select to authenticated using (true);
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy locations_select_allowed on public.locations
for select to authenticated using (
  owner_id = (select auth.uid())
  or (status = 'approved' and visibility in ('public', 'unlisted'))
);
create policy locations_insert_self_draft on public.locations
for insert to authenticated with check (
  owner_id = (select auth.uid()) and status = 'draft'
);
create policy locations_update_self_draft on public.locations
for update to authenticated
using (owner_id = (select auth.uid()) and status in ('draft', 'rejected'))
with check (owner_id = (select auth.uid()) and status in ('draft', 'rejected'));
create policy locations_delete_self_draft on public.locations
for delete to authenticated
using (owner_id = (select auth.uid()) and status in ('draft', 'rejected'));

create policy comments_select_allowed on public.comments
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
for update to authenticated
using (author_id = (select auth.uid()) and status = 'visible')
with check (author_id = (select auth.uid()) and status = 'visible');
create policy comments_delete_self on public.comments
for delete to authenticated using (author_id = (select auth.uid()));

create policy location_photos_select_allowed on public.location_photos
for select to authenticated using (
  uploader_id = (select auth.uid())
  or (status = 'visible' and public.can_view_location(location_id))
);
create policy location_photos_insert_owner on public.location_photos
for insert to authenticated with check (
  uploader_id = (select auth.uid())
  and status = 'pending'
  and public.owns_location(location_id)
);
create policy location_photos_update_self on public.location_photos
for update to authenticated
using (uploader_id = (select auth.uid()))
with check (uploader_id = (select auth.uid()));
create policy location_photos_delete_self on public.location_photos
for delete to authenticated using (uploader_id = (select auth.uid()));

create policy check_ins_select_self on public.check_ins
for select to authenticated using (user_id = (select auth.uid()));

create policy follows_select_authenticated on public.follows
for select to authenticated using (true);
create policy follows_insert_self on public.follows
for insert to authenticated with check (
  follower_id = (select auth.uid()) and follower_id <> following_id
);
create policy follows_delete_self on public.follows
for delete to authenticated using (follower_id = (select auth.uid()));

create policy notifications_select_self on public.notifications
for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_update_self on public.notifications
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy achievements_select_self on public.user_achievements
for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.redeem_invite(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  invite_row public.invites%rowtype;
begin
  if uid is null then raise exception 'authentication required'; end if;

  select * into invite_row from public.invites
  where code = upper(btrim(p_code))
    and uses < max_uses
    and (expires_at is null or expires_at > now())
  for update;

  if invite_row.code is null then raise exception 'invalid or expired invite'; end if;

  insert into public.invite_redemptions (code, user_id)
  values (invite_row.code, uid)
  on conflict (user_id) do nothing;

  if not found then raise exception 'invite already redeemed'; end if;

  update public.invites set uses = uses + 1 where code = invite_row.code;
  update public.profiles
  set invite_redeemed = true, invited_by = invite_row.created_by
  where id = uid;
end
$$;

create or replace function public.create_invite()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  generated_code text;
begin
  if uid is null then raise exception 'authentication required'; end if;

  update public.profiles set invite_balance = invite_balance - 1
  where id = uid and invite_redeemed and invite_balance > 0;
  if not found then raise exception 'invite balance exhausted'; end if;

  generated_code := upper(substr(
    md5(uid::text || clock_timestamp()::text || random()::text), 1, 10
  ));
  insert into public.invites (code, created_by, max_uses)
  values (generated_code, uid, 1);
  return generated_code;
end
$$;

create or replace function public.set_follow_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  new.follower_id := auth.uid();
  new.created_at := now();
  return new;
end
$$;

drop trigger if exists follows_set_actor on public.follows;
create trigger follows_set_actor
before insert on public.follows
for each row execute function public.set_follow_actor();

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (username, name, display_name, avatar_url) on public.profiles
  to authenticated;

revoke all on public.locations from anon, authenticated;
grant select on public.locations to authenticated;
grant insert (name, description, position, visibility, category,
  road_difficulty, has_parking, safety, image_url) on public.locations
  to authenticated;
grant update (name, description, position, visibility, category,
  road_difficulty, has_parking, safety, image_url) on public.locations
  to authenticated;
grant delete on public.locations to authenticated;

revoke all on public.comments from anon, authenticated;
grant select on public.comments to authenticated;
grant insert (location_id, parent_id, body, rating) on public.comments
  to authenticated;
grant update (body, rating) on public.comments to authenticated;
grant delete on public.comments to authenticated;

revoke all on public.location_photos from anon, authenticated;
grant select on public.location_photos to authenticated;
grant insert (location_id, storage_path, caption, sort_order)
  on public.location_photos to authenticated;
grant update (caption, sort_order) on public.location_photos to authenticated;
grant delete on public.location_photos to authenticated;

revoke all on public.check_ins from anon, authenticated;
grant select on public.check_ins to authenticated;

revoke all on public.follows from anon, authenticated;
grant select on public.follows to authenticated;
grant insert (following_id) on public.follows to authenticated;
grant delete on public.follows to authenticated;

revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (is_read) on public.notifications to authenticated;

revoke all on public.user_achievements from anon, authenticated;
grant select on public.user_achievements to authenticated;

create or replace function public.notify_location_owner_about_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  location_owner uuid;
  location_name text;
begin
  select l.owner_id, l.name into location_owner, location_name
  from public.locations l where l.id = new.location_id;

  if location_owner is null or location_owner = new.author_id then
    return new;
  end if;

  insert into public.notifications (user_id, title, message)
  values (
    location_owner,
    'Новий відгук',
    'До локації «' || left(coalesce(location_name, 'Без назви'), 100)
      || '» додано новий коментар.'
  );
  return new;
end
$$;

drop trigger if exists comments_notify_location_owner on public.comments;
create trigger comments_notify_location_owner
after insert on public.comments
for each row execute function public.notify_location_owner_about_comment();

revoke all on function public.notify_location_owner_about_comment()
  from public;
revoke all on function public.set_follow_actor() from public;
revoke all on function public.redeem_invite(text) from public;
revoke all on function public.create_invite() from public;
grant execute on function public.redeem_invite(text) to authenticated;
grant execute on function public.create_invite() to authenticated;

commit;
