-- Run in the `test` or `production` database as a superuser.
-- Exposes development.raw as foreign tables in this database's `raw` schema,
-- owned by the environment's dbt user. Safe to re-run: updates the password
-- and imports any raw tables that are not linked yet.
--
--   psql -d test -v env_user=test_user -v reader_password=... -f setup/02_link_raw.sql
\set ON_ERROR_STOP on

create extension if not exists postgres_fdw;

create server if not exists raw_source
    foreign data wrapper postgres_fdw
    options (host 'localhost', port '5432', dbname 'development');

grant usage on foreign server raw_source to :"env_user";

create user mapping if not exists for :"env_user" server raw_source
    options (user 'raw_reader', password :'reader_password');
alter user mapping for :"env_user" server raw_source
    options (set password :'reader_password');

create schema if not exists raw authorization :"env_user";

set role :"env_user";

-- Import only tables that are not linked yet (existing ones may have
-- dbt views depending on them).
select coalesce(
           'except (' || string_agg(quote_ident(foreign_table_name), ', ') || ')',
           '') as except_clause
from information_schema.foreign_tables
where foreign_table_schema = 'raw' \gset

import foreign schema raw :except_clause from server raw_source into raw;

reset role;
