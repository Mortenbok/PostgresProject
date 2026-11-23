-- Lead -> opportunity -> customer -> revenue funnel, one row per lead source
-- and month of the person's first lead. Counts people (primary leads), not
-- raw lead records, so duplicate leads do not inflate the funnel.
with people as (
    select
        lead_id,
        customer_id,
        lead_source,
        date_trunc('month', created_on)::date  as lead_month,
        status in ('qualified', 'converted') or opportunity_count > 0  as is_qualified,
        opportunity_count > 0                  as has_opportunity
    from {{ ref('dim_leads') }}
    where is_primary_lead
)

select
    p.lead_month,
    p.lead_source,
    count(*)                                               as leads,
    count(*) filter (where p.is_qualified)                 as qualified_leads,
    count(*) filter (where p.has_opportunity)              as leads_with_opportunity,
    count(*) filter (where p.customer_id is not null)      as customers,
    coalesce(sum(c.won_opportunity_amount_dkk), 0)         as won_opportunity_amount_dkk,
    coalesce(sum(c.lifetime_revenue_dkk), 0)               as customer_revenue_dkk,
    round(count(*) filter (where p.customer_id is not null)::numeric / count(*), 3)
                                                           as lead_to_customer_rate
from people as p
left join {{ ref('dim_customers') }} as c
    on c.customer_id = p.customer_id
group by p.lead_month, p.lead_source
