begin;

alter table public.reviews
  alter column rating drop not null;

alter table public.reviews
  drop constraint if exists reviews_location_id_author_id_key;

create index if not exists reviews_location_created_idx
  on public.reviews(location_id, created_at desc);

commit;
