-- Adds canonical transport_mode persistence to public.routes so a saved
-- route can be reopened in the same mode (walking/driving) it was created
-- in. Backward compatible: existing rows default to 'driving', preserving
-- their current (pre-existing) rendering behavior.

alter table public.routes
  add column if not exists transport_mode text not null default 'driving';

alter table public.routes
  add constraint routes_transport_mode_canonical_check
  check (transport_mode in ('driving', 'walking'));

-- routes has column-level (not table-level-only) grants for authenticated;
-- a new column is not covered by the existing table grant automatically,
-- so it needs its own minimal column-level grant, scoped to this column only.
grant select (transport_mode), insert (transport_mode), update (transport_mode)
  on public.routes to authenticated;
