-- depends_on: {{ ref('region_access') }}  (used by the secure_mart post-hook)
select
    product_id,
    product_name,
    category,
    list_price_dkk
from {{ ref('stg_products') }}
