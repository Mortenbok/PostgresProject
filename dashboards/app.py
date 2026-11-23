"""Test dashboards for the security on the marts.

Pick a demo login in the sidebar; every query runs as that Postgres role, so
what you see is exactly what row-level security and column grants allow.
Passwords come from pgpass.conf (setup/04_security_roles.sql).

    .\\.venv\\Scripts\\streamlit.exe run dashboards\\app.py
"""

import altair as alt
import pandas as pd
import psycopg
import streamlit as st
from psycopg.types.numeric import FloatLoader

LOGINS = {
    "demo_analyst": "analyst_all: all countries, all columns",
    "demo_nordics": "sales_nordics: DK, NO, SE; no names or emails",
    "demo_europe": "sales_europe: DE, NL, FR; no names or emails",
}
DATABASES = ["development", "test", "production"]

st.set_page_config(page_title="Mart security test", page_icon=":lock:", layout="wide")


# ------------------------------------------------------------------ data access
@st.cache_resource(show_spinner=False)
def connect(user: str, db: str) -> psycopg.Connection:
    # No password argument: libpq reads it from pgpass.conf.
    conn = psycopg.connect(host="localhost", port=5432, dbname=db, user=user, autocommit=True)
    # Load Postgres numeric as float instead of Decimal, so pandas/charts treat it as a number.
    conn.adapters.register_loader("numeric", FloatLoader)
    return conn


@st.cache_data(ttl=60, show_spinner=False)
def run(user: str, db: str, sql: str) -> pd.DataFrame:
    with connect(user, db).cursor() as cur:
        cur.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])


def query(user: str, db: str, sql: str) -> tuple[pd.DataFrame | None, str | None]:
    """Run as `user`; return (rows, None) or (None, Postgres error message)."""
    try:
        return run(user, db, sql), None
    except psycopg.errors.InsufficientPrivilege as e:
        return None, str(e).splitlines()[0]


def must(sql: str) -> pd.DataFrame:
    df, err = query(user, db, sql)
    if err:
        st.error(f"Not allowed: {err}")
        st.stop()
    return df


# --------------------------------------------------------------------- sidebar
with st.sidebar:
    st.header("Log in as")
    user = st.radio("Demo login", list(LOGINS), format_func=lambda u: u, label_visibility="collapsed")
    st.caption(LOGINS[user])
    db = st.selectbox("Database", DATABASES)
    if st.button("Refresh data"):
        st.cache_data.clear()

try:
    connect(user, db)
except psycopg.OperationalError as e:
    st.error(f"Could not log in as {user} to {db}: {str(e).strip().splitlines()[-1]}")
    st.stop()

me = must("""
    select current_user as login,
           (select string_agg(r.rolname, ', ') from pg_roles r
             where r.rolname in ('analyst_all', 'sales_nordics', 'sales_europe')
               and pg_has_role(current_user, r.oid, 'MEMBER')) as groups,
           (select string_agg(distinct country_code, ', ' order by country_code)
              from marts.dim_customers) as countries
""").iloc[0]

st.title("Shop & CRM dashboards")
st.markdown(
    f"Logged in to **{db}** as **{me.login}** (group **{me.groups or 'none'}**). "
    f"Countries visible: **{me.countries or 'none'}**"
)

sales, customers, pipeline, funnel, access = st.tabs(
    ["Sales", "Customers", "Pipeline", "Funnel", "Access check"]
)

# ----------------------------------------------------------------------- sales
with sales:
    k = must("""
        select coalesce(sum(line_amount_dkk) filter (where is_revenue), 0)::float8 as revenue,
               count(distinct order_id)    as orders,
               count(distinct customer_id) as customers
        from marts.fct_order_lines
    """).iloc[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Revenue (DKK)", f"{k.revenue:,.0f}")
    c2.metric("Orders", f"{int(k.orders):,}")
    c3.metric("Ordering customers", f"{int(k.customers):,}")
    c4.metric("Revenue per order (DKK)", f"{k.revenue / k.orders:,.0f}" if k.orders else "-")

    by_month = must("""
        select date_trunc('month', ordered_on)::date as month, country_code,
               sum(line_amount_dkk)::float8 as revenue_dkk
        from marts.fct_order_lines
        where is_revenue
        group by 1, 2
    """)
    st.subheader("Revenue by month and country")
    st.altair_chart(
        alt.Chart(by_month).mark_bar().encode(
            x=alt.X("yearmonth(month):T", title=None),
            y=alt.Y("sum(revenue_dkk):Q", title="Revenue (DKK)"),
            color=alt.Color("country_code:N", title="Country"),
            tooltip=["yearmonth(month):T", "country_code", alt.Tooltip("sum(revenue_dkk):Q", format=",.0f")],
        ),
    )

    left, right = st.columns(2)
    with left:
        st.subheader("Revenue by country")
        st.bar_chart(by_month.groupby("country_code")["revenue_dkk"].sum(), horizontal=True)
    with right:
        st.subheader("Revenue by product category")
        cat = must("""
            select p.category, sum(l.line_amount_dkk)::float8 as revenue_dkk
            from marts.fct_order_lines l
            join marts.dim_products p using (product_id)
            where l.is_revenue
            group by 1
        """)
        st.bar_chart(cat.set_index("category")["revenue_dkk"], horizontal=True)

# ------------------------------------------------------------------- customers
with customers:
    k = must("""
        select count(*) as customers,
               count(*) filter (where acquisition_source <> 'direct') as from_leads,
               coalesce(sum(lifetime_revenue_dkk), 0)::float8 as revenue
        from marts.dim_customers
    """).iloc[0]
    c1, c2, c3 = st.columns(3)
    c1.metric("Customers", f"{int(k.customers):,}")
    c2.metric("Came in via a lead", f"{int(k.from_leads):,}")
    c3.metric("Lifetime revenue (DKK)", f"{k.revenue:,.0f}")

    st.subheader("Customers by acquisition source")
    src = must("select acquisition_source, count(*) as customers from marts.dim_customers group by 1")
    st.bar_chart(src.set_index("acquisition_source")["customers"], horizontal=True)

    st.subheader("Top customers by lifetime revenue")
    cols = """country_code, acquisition_source, order_count,
              lifetime_revenue_dkk::float8 as lifetime_revenue_dkk, first_order_on"""
    top, err = query(user, db, f"""
        select customer_id, full_name, email, {cols}
        from marts.dim_customers order by lifetime_revenue_dkk desc limit 20""")
    if err:
        st.info("Names and emails are hidden for your group (column privileges).")
        top = must(f"select customer_id, {cols} from marts.dim_customers order by lifetime_revenue_dkk desc limit 20")
    st.dataframe(top, hide_index=True, width="stretch")

# -------------------------------------------------------------------- pipeline
with pipeline:
    k = must("""
        select count(*) as opps,
               count(*) filter (where not is_closed) as open_opps,
               coalesce(sum(amount_dkk) filter (where is_won), 0)::float8 as won,
               coalesce(sum(amount_dkk) filter (where not is_closed), 0)::float8 as open_amount
        from marts.fct_opportunities
    """).iloc[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Opportunities", f"{int(k.opps):,}")
    c2.metric("Open", f"{int(k.open_opps):,}")
    c3.metric("Won (DKK)", f"{k.won:,.0f}")
    c4.metric("Open pipeline (DKK)", f"{k.open_amount:,.0f}")

    stages = ["prospecting", "proposal", "negotiation", "closed_won", "closed_lost"]
    opp = must("""
        select stage, sales_owner, count(*) as opportunities, sum(amount_dkk)::float8 as amount_dkk
        from marts.fct_opportunities group by 1, 2
    """)
    st.subheader("Opportunities by stage and sales owner")
    st.altair_chart(
        alt.Chart(opp).mark_bar().encode(
            x=alt.X("stage:N", sort=stages, title=None),
            y=alt.Y("sum(opportunities):Q", title="Opportunities"),
            color=alt.Color("sales_owner:N", title="Owner"),
            tooltip=["stage", "sales_owner", "opportunities", alt.Tooltip("amount_dkk:Q", format=",.0f")],
        ),
    )

    st.subheader("Open opportunities")
    cols = "opportunity_id, country_code, lead_source, sales_owner, stage, amount_dkk::float8 as amount_dkk, close_on"
    rows, err = query(user, db, f"""
        select opportunity_name, {cols} from marts.fct_opportunities
        where not is_closed order by amount_dkk desc""")
    if err:
        st.info("Opportunity names are hidden for your group (they contain people's surnames).")
        rows = must(f"select {cols} from marts.fct_opportunities where not is_closed order by amount_dkk desc")
    st.dataframe(rows, hide_index=True, width="stretch")

# ---------------------------------------------------------------------- funnel
with funnel:
    f = must("""
        select lead_source,
               sum(leads) as leads,
               sum(qualified_leads) as qualified,
               sum(leads_with_opportunity) as with_opportunity,
               sum(customers) as customers,
               sum(customer_revenue_dkk)::float8 as customer_revenue_dkk
        from marts.rpt_funnel_by_source
        group by 1
        order by leads desc
    """)
    total = f[["leads", "qualified", "with_opportunity", "customers"]].sum()
    st.subheader("Lead funnel (people, not lead records)")
    steps = pd.DataFrame({"step": total.index, "people": total.values})
    st.altair_chart(
        alt.Chart(steps).mark_bar().encode(
            y=alt.Y("step:N", sort=list(total.index), title=None),
            x=alt.X("people:Q", title="People"),
            tooltip=["step", "people"],
        ),
    )
    st.subheader("By lead source")
    f["lead_to_customer"] = (f["customers"] / f["leads"]).round(3)
    st.dataframe(f, hide_index=True, width="stretch")

# ---------------------------------------------------------------- access check
with access:
    st.markdown(
        "Each check runs as the login shown at the top of the column. ✅ = allowed, "
        "⛔ = refused by Postgres. Row counts show what row-level security lets through."
    )
    checks = {
        "dim_customers rows": "select count(*) from marts.dim_customers",
        "dim_leads rows": "select count(*) from marts.dim_leads",
        "fct_orders rows": "select count(*) from marts.fct_orders",
        "fct_order_lines rows": "select count(*) from marts.fct_order_lines",
        "fct_opportunities rows": "select count(*) from marts.fct_opportunities",
        "rpt_funnel leads": "select sum(leads)::int from marts.rpt_funnel_by_source",
        "dim_products rows": "select count(*) from marts.dim_products",
        "Countries visible": "select string_agg(distinct country_code, ',' order by country_code) from marts.dim_customers",
        "Customer email (PII)": "select count(email) from marts.dim_customers",
        "Lead full_name (PII)": "select count(full_name) from marts.dim_leads",
        "Opportunity name (PII)": "select count(opportunity_name) from marts.fct_opportunities",
        "staging.stg_customers": "select count(*) from staging.stg_customers",
        "intermediate.int_leads_matched": "select count(*) from intermediate.int_leads_matched",
        "raw.raw_customers": "select count(*) from raw.raw_customers",
    }
    table = {}
    for login in LOGINS:
        col = []
        for sql in checks.values():
            try:
                df, err = query(login, db, sql)
            except psycopg.Error as e:  # e.g. schema missing in this database
                df, err = None, str(e).splitlines()[0]
            col.append(f"⛔ {err}" if err else f"✅ {df.iat[0, 0]}")
        table[login] = col
    st.dataframe(pd.DataFrame(table, index=list(checks)), width="stretch")
