-- Ordered, owner-scoped route persistence for the multi-waypoint editor.
alter table public.routes
  alter column id set default gen_random_uuid()::text,
  alter column author_id set default auth.uid()::text,
  alter column points set not null;

alter table public.routes
  add constraint routes_points_is_array
  check (jsonb_typeof(points) = 'array') not valid;

alter table public.routes validate constraint routes_points_is_array;

create policy routes_owner_select on public.routes
  for select to authenticated
  using (author_id = auth.uid()::text);

create policy routes_owner_insert on public.routes
  for insert to authenticated
  with check (
    author_id = auth.uid()::text
    and jsonb_array_length(points) >= 2
  );

create policy routes_owner_update on public.routes
  for update to authenticated
  using (author_id = auth.uid()::text)
  with check (
    author_id = auth.uid()::text
    and jsonb_array_length(points) >= 2
  );

create policy routes_owner_delete on public.routes
  for delete to authenticated
  using (author_id = auth.uid()::text);

grant select, insert, update, delete
  on table public.routes to authenticated;

-- Rollback:
-- drop policy routes_owner_select on public.routes;
-- drop policy routes_owner_insert on public.routes;
-- drop policy routes_owner_update on public.routes;
-- drop policy routes_owner_delete on public.routes;
-- alter table public.routes drop constraint routes_points_is_array;
-- revoke select, insert, update, delete on public.routes from authenticated;
-- alter table public.routes alter column id drop default;
-- alter table public.routes alter column author_id drop default;
