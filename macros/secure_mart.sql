{#
  Post-hook for mart tables: grants access to the groups in
  var('full_access_roles') / var('restricted_roles') and, optionally, adds
  row-level security by country.

    country_column  Column holding the row's country code. When set, row-level
                    security is enabled and a group sees only the countries
                    seeds/region_access.csv lists for it ('*' = all).
                    None = no row filter (e.g. dim_products).
    pii_columns     Columns restricted groups may not select (column grants).
                    Full-access groups can select every column.

  dbt drops and recreates mart tables on every run, which removes grants and
  policies, so this runs as a post-hook each time. The table owner (the dbt
  user) bypasses row-level security, so downstream models still see all rows.

  Models that use it must depend on the seed:  -- depends_on: {{ ref('region_access') }}
#}
{% macro secure_mart(country_column=none, pii_columns=[]) %}
    {%- set full = var('full_access_roles') -%}
    {%- set restricted = var('restricted_roles') -%}
    {%- set everyone = (full + restricted) | join(', ') -%}

    {#- USAGE on the schema is granted once in on-run-end (grant_marts_usage);
        granting it here from parallel threads fails with "tuple concurrently updated". #}
    grant select on {{ this }} to {{ full | join(', ') }};

    {%- if restricted %}
        {%- if pii_columns %}
            {#- Column grants: every column except the PII ones. Columns are
                looked up at run time, so new columns are granted automatically. -#}
            {%- set pii = pii_columns | map('lower') | list -%}
            {%- set allowed = [] -%}
            {%- if execute -%}
                {%- for col in adapter.get_columns_in_relation(this) -%}
                    {%- if col.name | lower not in pii -%}
                        {%- do allowed.append(adapter.quote(col.name)) -%}
                    {%- endif -%}
                {%- endfor -%}
            {%- endif %}
    {%- if allowed %}
    grant select ({{ allowed | join(', ') }}) on {{ this }} to {{ restricted | join(', ') }};
    {%- endif %}
        {%- else %}
    grant select on {{ this }} to {{ restricted | join(', ') }};
        {%- endif %}
    {%- endif %}

    {%- if country_column %}
    alter table {{ this }} enable row level security;
    drop policy if exists region_access on {{ this }};
    create policy region_access on {{ this }}
        for select
        to {{ everyone }}
        using (
            exists (
                select 1
                from {{ ref('region_access') }} as a
                {#- Qualify with the table name: unqualified, the column would
                    resolve to region_access.country_code and match every row. #}
                where a.country_code in ('*', {{ adapter.quote(this.identifier) }}.{{ adapter.quote(country_column) }}::text)
                  and pg_has_role(current_user, a.group_role, 'MEMBER')
            )
        );
    {%- endif %}
{% endmacro %}


{# on-run-end: let every access group into the marts schema (once per run). #}
{% macro grant_marts_usage() %}
    {%- set roles = (var('full_access_roles') + var('restricted_roles')) | join(', ') -%}
    {%- set schemas = [] -%}
    {%- if not execute %}{{ return('') }}{% endif -%}
    {%- for node in graph.nodes.values()
            if node.resource_type == 'model' and node.fqn[1] == 'marts' -%}
        {%- if node.schema not in schemas %}{% do schemas.append(node.schema) %}{% endif -%}
    {%- endfor -%}
    {%- for s in schemas %}
    grant usage on schema {{ adapter.quote(s) }} to {{ roles }};
    {%- endfor %}
{% endmacro %}
