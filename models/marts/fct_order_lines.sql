-- depends_on: {{ ref('region_access') }}  (used by the secure_mart post-hook)
select
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    c.country_code,
    oi.product_id,
    o.ordered_on,
    o.status,
    oi.quantity,
    oi.unit_price_dkk,
    oi.quantity * oi.unit_price_dkk  as line_amount_dkk,
    o.status in (
        {%- for s in var('revenue_statuses') %}'{{ s }}'{% if not loop.last %}, {% endif %}{% endfor -%}
    )                                as is_revenue
from {{ ref('stg_order_items') }} as oi
join {{ ref('stg_orders') }} as o
    on o.order_id = oi.order_id
join {{ ref('stg_customers') }} as c
    on c.customer_id = o.customer_id
