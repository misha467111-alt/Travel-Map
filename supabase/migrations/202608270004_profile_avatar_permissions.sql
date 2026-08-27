-- Profile editing + dedicated avatar storage for the existing production schema.
-- Forward-only and safe to re-run. No user data is deleted.

-- The client only updates these profile columns. System fields stay unavailable.
revoke update on public.profiles from authenticated;
grant select on public.profiles to authenticated;
grant update(username, name, display_name, avatar_url) on public.profiles to authenticated;

-- Ensure an authenticated user can update only their own canonical profile row.
alter table public.profiles enable row level security;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Dedicated public avatar bucket. Objects are still write-protected by owner folder.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict(id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatars_public_read on storage.objects;
drop policy if exists avatars_owner_insert on storage.objects;
drop policy if exists avatars_owner_update on storage.objects;
drop policy if exists avatars_owner_delete on storage.objects;

create policy avatars_public_read
on storage.objects for select
to public
using (bucket_id = 'avatars');

create policy avatars_owner_insert
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy avatars_owner_update
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy avatars_owner_delete
on storage.objects for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);
