-- depends_on: {{ ref('region_access') }}  (used by the secure_mart post-hook)
with lines as (
    select
        order_id,
        count(*)              as line_count,
        sum(quantity)         as item_count,
        sum(line_amount_dkk)  as order_amount_dkk
    from {{ ref('fct_order_lines') }}
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    c.country_code,
    o.ordered_on,
    o.status,
    coalesce(l.line_count, 0)        as line_count,
    coalesce(l.item_count, 0)        as item_count,
    coalesce(l.order_amount_dkk, 0)  as order_amount_dkk
from {{ ref('stg_orders') }} as o
join {{ ref('stg_customers') }} as c
    on c.customer_id = o.customer_id
left join lines as l
    on l.order_id = o.order_id
