-- Run in the `development` database as a superuser.
-- Creates/updates the read-only role that test and production use (via
-- postgres_fdw) to read development.raw.
--
--   psql -d development -v reader_password=... -f setup/01_raw_reader_role.sql
\set ON_ERROR_STOP on

select not exists (select from pg_roles where rolname = 'raw_reader') as need_role \gset
\if :need_role
    create role raw_reader login;
\endif
alter role raw_reader with login password :'reader_password';

grant connect on database development to raw_reader;
grant usage on schema raw to raw_reader;
grant select on all tables in schema raw to raw_reader;
-- Tables added to raw later by development_user are readable too.
alter default privileges for role development_user in schema raw
    grant select on tables to raw_reader;
