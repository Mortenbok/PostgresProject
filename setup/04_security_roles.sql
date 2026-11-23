-- Run once as a superuser (any database). Roles are cluster-wide, so the same
-- groups work in development, test and production.
--
-- Creates the access groups the marts are secured for, plus one demo login per
-- group for testing (the Streamlit dashboards log in as these).
--
--   psql -d postgres -v analyst_password=... -v nordics_password=... \
--        -v europe_password=... -f setup/04_security_roles.sql
--
-- Re-running is safe; it resets the demo passwords.
--
-- Groups (NOLOGIN) and what dbt grants them on the marts
-- (macros/secure_mart.sql, seeds/region_access.csv):
--   analyst_all    all rows, all columns
--   sales_nordics  DK, NO, SE rows only; no name/email columns
--   sales_europe   DE, NL, FR rows only; no name/email columns
-- staging, intermediate and raw are not granted to any group.
\set ON_ERROR_STOP on

-- ---------------------------------------------------------------- groups
select not exists (select from pg_roles where rolname = 'analyst_all')   as need_analyst \gset
select not exists (select from pg_roles where rolname = 'sales_nordics') as need_nordics \gset
select not exists (select from pg_roles where rolname = 'sales_europe')  as need_europe \gset
\if :need_analyst
    create role analyst_all nologin;
\endif
\if :need_nordics
    create role sales_nordics nologin;
\endif
\if :need_europe
    create role sales_europe nologin;
\endif

grant connect on database development, test, production
    to analyst_all, sales_nordics, sales_europe;

-- ----------------------------------------------------------- demo logins
select not exists (select from pg_roles where rolname = 'demo_analyst') as need_demo_analyst \gset
select not exists (select from pg_roles where rolname = 'demo_nordics') as need_demo_nordics \gset
select not exists (select from pg_roles where rolname = 'demo_europe')  as need_demo_europe \gset
\if :need_demo_analyst
    create role demo_analyst login;
\endif
\if :need_demo_nordics
    create role demo_nordics login;
\endif
\if :need_demo_europe
    create role demo_europe login;
\endif

alter role demo_analyst with login password :'analyst_password';
alter role demo_nordics with login password :'nordics_password';
alter role demo_europe  with login password :'europe_password';

grant analyst_all   to demo_analyst;
grant sales_nordics to demo_nordics;
grant sales_europe  to demo_europe;
