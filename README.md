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
