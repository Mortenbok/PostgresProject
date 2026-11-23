with opps as (
    select
        lead_id,
        count(*)                                     as opportunity_count,
        count(*) filter (where is_won)               as won_opportunity_count,
        coalesce(sum(amount_dkk) filter (where is_won), 0)  as won_amount_dkk,
        min(created_on)                              as first_opportunity_on
    from {{ ref('fct_opportunities') }}
    group by lead_id
)

select
    l.lead_id,
    l.full_name,
    l.email,
    l.country_code,
    l.lead_source,
    l.status,
    l.created_on,
    l.converted_on,
    l.customer_id,
    l.is_customer,
    l.is_primary_lead,
    coalesce(o.opportunity_count, 0)      as opportunity_count,
    coalesce(o.won_opportunity_count, 0)  as won_opportunity_count,
    coalesce(o.won_amount_dkk, 0)         as won_amount_dkk,
    o.first_opportunity_on
from {{ ref('int_leads_matched') }} as l
left join opps as o
    on o.lead_id = l.lead_id
