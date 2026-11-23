with source as (
    select
        *,
        -- 'Closed Won', 'closed won', 'Closed-Won' -> 'closed_won'
        lower(regexp_replace(trim(stage), '[\s-]+', '_', 'g')) as stage_clean
    from {{ source('raw', 'raw_opportunities') }}
)

select
    id                                         as opportunity_id,
    lead_id,
    name                                       as opportunity_name,
    stage_clean                                as stage,
    stage_clean in ('closed_won', 'closed_lost')  as is_closed,
    stage_clean = 'closed_won'                 as is_won,
    amount_dkk::numeric(12, 2)                 as amount_dkk,
    owner                                      as sales_owner,
    created_at                                 as created_on,
    close_date                                 as close_on
from source
