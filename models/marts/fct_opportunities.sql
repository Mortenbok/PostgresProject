-- depends_on: {{ ref('region_access') }}  (used by the secure_mart post-hook)
select
    o.opportunity_id,
    o.lead_id,
    l.customer_id,
    l.lead_source,
    l.country_code,
    o.opportunity_name,
    o.sales_owner,
    o.stage,
    o.is_closed,
    o.is_won,
    o.amount_dkk,
    o.created_on,
    o.close_on,
    case when o.is_closed then o.close_on - o.created_on end  as days_to_close
from {{ ref('stg_opportunities') }} as o
join {{ ref('int_leads_matched') }} as l
    on l.lead_id = o.lead_id
