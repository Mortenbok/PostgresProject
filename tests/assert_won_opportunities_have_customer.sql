-- Stitching check: a won opportunity should belong to a lead whose email
-- matches a customer. Rows returned here are won deals we cannot tie to the
-- shop (e.g. the customer used a different email). Warn rather than fail,
-- since this is a data-quality signal from the CRM, not a pipeline bug.
{{ config(severity='warn') }}

select opportunity_id, lead_id, opportunity_name, amount_dkk
from {{ ref('fct_opportunities') }}
where is_won
  and customer_id is null
