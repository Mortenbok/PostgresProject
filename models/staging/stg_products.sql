select
    id                         as product_id,
    name                       as product_name,
    category,
    price_dkk::numeric(12, 2)  as list_price_dkk
from {{ source('raw', 'raw_products') }}
