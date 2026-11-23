select
    id             as order_id,
    customer_id,
    ordered_at     as ordered_on,
    lower(status)  as status
from {{ source('raw', 'raw_orders') }}
