begin;

-- Keep extensions outside `public` so their objects are not exposed through
-- the Data API merely because the public schema is exposed.
create schema if not exists extensions;

create extension if not exists postgis with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;

commit;
