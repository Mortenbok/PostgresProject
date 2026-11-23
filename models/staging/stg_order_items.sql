select
    id                              as order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price_dkk::numeric(12, 2)  as unit_price_dkk
from {{ source('raw', 'raw_order_items') }}
