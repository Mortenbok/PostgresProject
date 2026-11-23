select
    product_id,
    product_name,
    category,
    list_price_dkk
from {{ ref('stg_products') }}
