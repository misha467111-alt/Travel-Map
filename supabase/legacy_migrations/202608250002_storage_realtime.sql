insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('location-media','location-media',false,52428800,array['image/jpeg','image/webp','video/mp4'])
on conflict(id) do nothing;

create policy location_media_authenticated_read on storage.objects for select to authenticated
using(bucket_id='location-media');
create policy location_media_owner_upload on storage.objects for insert to authenticated
with check(bucket_id='location-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy location_media_owner_delete on storage.objects for delete to authenticated
using(bucket_id='location-media' and owner_id=auth.uid());

alter publication supabase_realtime add table public.place_conditions;
alter publication supabase_realtime add table public.route_stops;
alter publication supabase_realtime add table public.posts;
