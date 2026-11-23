with orders as (
    select
        customer_id,
        min(ordered_on)  as first_order_on,
        max(ordered_on)  as last_order_on,
        count(*)         as order_count
    from {{ ref('fct_orders') }}
    group by customer_id
),

revenue as (
    select
        customer_id,
        sum(line_amount_dkk)  as lifetime_revenue_dkk
    from {{ ref('fct_order_lines') }}
    where is_revenue
    group by customer_id
),

primary_lead as (
    select
        customer_id,
        lead_id,
        lead_source,
        created_on  as first_lead_on
    from {{ ref('int_leads_matched') }}
    where is_customer
      and is_primary_lead
),

won_opps as (
    select
        customer_id,
        count(*)         as won_opportunity_count,
        sum(amount_dkk)  as won_opportunity_amount_dkk
    from {{ ref('fct_opportunities') }}
    where is_won
      and customer_id is not null
    group by customer_id
)

select
    c.customer_id,
    c.full_name,
    c.email,
    c.country_code,
    c.signed_up_on,
    o.first_order_on,
    o.last_order_on,
    coalesce(o.order_count, 0)           as order_count,
    coalesce(r.lifetime_revenue_dkk, 0)  as lifetime_revenue_dkk,
    -- CRM attribution (null for customers that did not come in via a lead)
    pl.lead_id,
    coalesce(pl.lead_source, 'direct')   as acquisition_source,
    pl.first_lead_on,
    least(c.signed_up_on, o.first_order_on) - pl.first_lead_on  as days_lead_to_customer,
    coalesce(w.won_opportunity_count, 0)       as won_opportunity_count,
    coalesce(w.won_opportunity_amount_dkk, 0)  as won_opportunity_amount_dkk
from {{ ref('stg_customers') }} as c
left join orders as o
    on o.customer_id = c.customer_id
left join revenue as r
    on r.customer_id = c.customer_id
left join primary_lead as pl
    on pl.customer_id = c.customer_id
left join won_opps as w
    on w.customer_id = c.customer_id
