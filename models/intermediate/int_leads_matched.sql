-- Stitches CRM leads to shop customers. There is no shared id, so the match
-- is on normalised email (both sides lower-cased and trimmed). One person can
-- have several leads; the earliest one is their primary lead and is used for
-- attribution (lead source, lead date).
select
    l.*,
    c.customer_id,
    c.customer_id is not null  as is_customer,
    row_number() over (
        partition by l.email
        order by l.created_on, l.lead_id
    ) = 1                      as is_primary_lead
from {{ ref('stg_leads') }} as l
left join {{ ref('stg_customers') }} as c
    on trim(c.email) = l.email
