-- The parts of Supabase that schema.sql leans on, for a local Postgres.
--
-- Supabase provides `auth.users`, `auth.uid()` and the `anon` and
-- `authenticated` roles. A plain Postgres does not, so the tests stand them up
-- themselves. `auth.uid()` here reads the same setting PostgREST sets from the
-- bearer token, which is what lets a test say who is calling.
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
end $$;
