# postgres_project (dbt)

dbt project for the local PostgreSQL 19 server (`localhost:5432`).

| Target | Database      | User               |
|--------|---------------|--------------------|
| `dev`  | `development` | `development_user` |
| `test` | `test`        | `test_user`        |
| `prod` | `production`  | `production_user`  |

## Layout

```
raw           (sources, loaded outside dbt)
  -> staging      (views)   stg_customers, stg_orders, stg_order_items, stg_products,
                            stg_leads, stg_opportunities
  -> intermediate (views)   int_leads_matched
  -> marts        (tables)  fct_order_lines, fct_orders, fct_opportunities,
                            dim_customers, dim_products, dim_leads,
                            rpt_funnel_by_source
```

### How CRM and shop data are stitched

```
lead --(lead_id)--> opportunity
  |
  +--(email, lower-cased + trimmed)--> customer --> orders --> revenue
```

- Leads and customers share no id; `int_leads_matched` joins them on
  normalised email and flags each person's earliest lead as `is_primary_lead`.
- `dim_customers` gains `acquisition_source` (primary lead's source, or
  `direct`), `days_lead_to_customer` and won-opportunity totals.
- `rpt_funnel_by_source` counts people (primary leads), not lead records:
  leads -> qualified -> with opportunity -> customers -> revenue.
- `tests/assert_won_opportunities_have_customer.sql` warns about won deals
  that can't be tied to a shop customer.

The CRM data is generated sample data: `setup/03_crm_sample_data.sql`
(deterministic; run as `development_user`).

Schemas are named `staging` / `marts` in every environment
(see `macros/generate_schema_name.sql`). Revenue statuses are the
`revenue_statuses` var in `dbt_project.yml`.

## Setup

```powershell
uv venv .venv --python 3.12
uv pip install --python .venv -r requirements.txt
$env:DBT_PROFILES_DIR = "."        # use the repo's profiles.yml
.\.venv\Scripts\dbt.exe debug
```

Passwords are not stored in the repo. `profiles.yml` leaves the password empty,
so libpq reads `%APPDATA%\postgresql\pgpass.conf`. Set `DBT_PASSWORD` to override.

## Run

```powershell
.\.venv\Scripts\dbt.exe build                # dev (default)
.\.venv\Scripts\dbt.exe build --target test  # test
```

## CI/CD (GitHub Actions, self-hosted runner)

`.github/workflows/dbt.yml` runs on a self-hosted Windows runner on the PC that
hosts Postgres (label `postgres-local`), because GitHub's hosted runners can't
reach `localhost`.

| Git branch    | dbt target | Database      |
|---------------|------------|---------------|
| `development` | `dev`      | `development` |
| `test`        | `test`     | `test`        |
| `production`  | `prod`     | `production`  |

- Push to one of these branches -> `dbt build --target <target>`.
- Pull request into one of them -> `dbt compile` only (nothing is changed).
- Pull requests from forks never run on the runner. Keep the repo private:
  a self-hosted runner on a public repo can be abused via fork PRs.
- Run results (`run_results.json`, `manifest.json`, `dbt.log`) are uploaded as
  an artifact on every run.

Promotion flow: merge `development` -> `test` -> `production` via pull requests.

Runner setup (once): get a token from *Settings > Actions > Runners > New
self-hosted runner*, then

```powershell
powershell -ExecutionPolicy Bypass -File setup\register_runner.ps1 -Token <token>
```

This installs the runner in `%USERPROFILE%\actions-runner` and starts it as
your user at logon (scheduled task), so dbt can read your `pgpass.conf`. The
runner only works while you're logged in.

## Shared raw data

There is one real copy of the raw data: `development.raw`. In `test` and
`production`, `raw` is a schema of `postgres_fdw` foreign tables that read it
live through the read-only role `raw_reader`, so dbt's `source('raw', ...)`
works unchanged in every target. Writes to `raw` from test/prod are rejected.

Setup (as superuser; the password only needs to match across the three runs):

```powershell
psql -d development -v reader_password=$pw -f setup/01_raw_reader_role.sql
psql -d test       -v env_user=test_user       -v reader_password=$pw -f setup/02_link_raw.sql
psql -d production -v env_user=production_user -v reader_password=$pw -f setup/02_link_raw.sql
```

- New raw table in development: re-run `02_link_raw.sql` to link it.
- Column change on an existing raw table: drop that foreign table in test/prod
  (and dependent views; `dbt build` recreates them) and re-run `02_link_raw.sql`.
- test/prod builds need the development database to be up.

## Access security on the marts

Security sits on the marts, the layer people query. `raw`, `staging` and
`intermediate` are not granted to any group, so the rules can't be bypassed
by reading the layers below.

| Group (NOLOGIN) | Rows                         | PII columns |
|-----------------|------------------------------|-------------|
| `analyst_all`   | all countries                | visible     |
| `sales_nordics` | DK, NO, SE                   | hidden      |
| `sales_europe`  | DE, NL, FR                   | hidden      |

PII columns: `full_name` and `email` on `dim_customers` / `dim_leads`, and
`opportunity_name` on `fct_opportunities` (it starts with the person's
surname). `dim_products` is open to all groups.

How it is built:

- **Groups**: `setup/04_security_roles.sql` (superuser, once). Roles are
  cluster-wide, so the same groups work in all three databases. It also creates
  the demo logins `demo_analyst`, `demo_nordics`, `demo_europe`.
- **Which group sees which country**: `seeds/region_access.csv` (`*` = all).
  A country not listed is visible only to `*` groups.
- **Rows**: Postgres row-level security. `macros/secure_mart.sql` runs as a
  post-hook on each mart (configured in `models/marts/_marts.yml`) and
  re-creates the grants and the `region_access` policy every build, because
  dbt recreates the tables. Every mart has a `country_code` to filter on
  (customer's country for orders, lead's country for leads/opportunities/funnel).
- **Columns**: column grants. Restricted groups get `SELECT` on every column
  except the PII ones, so `select *` or `select email` fails for them.
- **Group lists**: vars `full_access_roles` / `restricted_roles` in
  `dbt_project.yml`.

The dbt user owns the tables and bypasses row-level security (downstream
models need all rows), so never test the rules logged in as it.

Add a group: add it to `04_security_roles.sql` and run it, add its countries
to `region_access.csv`, add it to one of the role vars, then `dbt build`.

### Test dashboards

`dashboards/app.py` is a Streamlit app that logs in as a demo login you pick
and shows sales, customers, pipeline and funnel dashboards plus an
*Access check* tab comparing all three logins side by side.

```powershell
uv pip install --python .venv -r dashboards/requirements.txt
.\.venv\Scripts\streamlit.exe run dashboards\app.py
```

The demo logins' passwords are in `pgpass.conf` (generated when the roles
were set up); re-running `04_security_roles.sql` with new passwords resets them.
