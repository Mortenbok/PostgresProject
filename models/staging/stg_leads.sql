select
    id                                               as lead_id,
    first_name,
    last_name,
    (first_name || ' ') || last_name                 as full_name,
    lower(trim(email))                               as email,
    upper(trim(country_code))                        as country_code,
    lower(regexp_replace(trim(lead_source), '[\s-]+', '_', 'g'))  as lead_source,
    lower(trim(status))                              as status,
    created_at                                       as created_on,
    converted_at                                     as converted_on
from {{ source('raw', 'raw_leads') }}
