begin;

alter table public.locations
  add column if not exists image_url text;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'location_images',
  'location_images',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists location_images_public_read on storage.objects;
create policy location_images_public_read
on storage.objects
for select
to public
using (bucket_id = 'location_images');

drop policy if exists location_images_authenticated_upload on storage.objects;
create policy location_images_authenticated_upload
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'location_images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Потрібна для видалення завантаженого файлу, якщо створення локації не вдалося.
drop policy if exists location_images_owner_delete on storage.objects;
create policy location_images_owner_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'location_images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Стару сигнатуру треба видалити, інакше виклик із параметрами за замовчуванням
-- може стати неоднозначним для PostgREST.
drop function if exists public.create_location_with_xp(
  text,
  text,
  double precision,
  double precision
);
drop function if exists public.create_location_with_xp(
  text,
  text,
  double precision,
  double precision,
  text
);

create function public.create_location_with_xp(
  location_title text,
  location_description text,
  location_latitude double precision,
  location_longitude double precision,
  p_image_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  created_location_id uuid;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if nullif(btrim(location_title), '') is null then
    raise exception 'location title is required';
  end if;
  if location_latitude not between -90 and 90
     or location_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  if p_image_url is not null and length(p_image_url) > 2048 then
    raise exception 'image URL is too long';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'locations'
      and column_name = 'user_id'
  ) then
    execute $insert$
      insert into public.locations (
        user_id,
        title,
        description,
        coordinates,
        image_url
      )
      values (
        $1,
        $2,
        $3,
        extensions.st_setsrid(
          extensions.st_makepoint($4, $5),
          4326
        )::extensions.geography,
        $6
      )
      returning id
    $insert$
    into created_location_id
    using
      current_user_id,
      btrim(location_title),
      coalesce(btrim(location_description), ''),
      location_longitude,
      location_latitude,
      nullif(btrim(p_image_url), '');
  else
    execute $insert$
      insert into public.locations (
        owner_id,
        name,
        description,
        position,
        image_url
      )
      values (
        $1,
        $2,
        $3,
        extensions.st_setsrid(
          extensions.st_makepoint($4, $5),
          4326
        )::extensions.geography,
        $6
      )
      returning id
    $insert$
    into created_location_id
    using
      current_user_id,
      btrim(location_title),
      coalesce(btrim(location_description), ''),
      location_longitude,
      location_latitude,
      nullif(btrim(p_image_url), '');
  end if;

  update public.profiles
  set
    xp = xp + 10,
    level = case
      when xp + 10 >= 500 then 'Мандрівник'
      when xp + 10 >= 100 then 'Дослідник'
      else 'Новачок'
    end
  where id = current_user_id;

  if not found then
    raise exception 'profile not found';
  end if;

  return created_location_id;
end;
$$;

revoke all on function public.create_location_with_xp(
  text,
  text,
  double precision,
  double precision,
  text
) from public;
grant execute on function public.create_location_with_xp(
  text,
  text,
  double precision,
  double precision,
  text
) to authenticated;

commit;
