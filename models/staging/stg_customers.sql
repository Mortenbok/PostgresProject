select
    id                                as customer_id,
    first_name,
    last_name,
    (first_name || ' ') || last_name  as full_name,
    lower(email)                      as email,
    upper(country_code)               as country_code,
    created_at                        as signed_up_on
from {{ source('raw', 'raw_customers') }}
