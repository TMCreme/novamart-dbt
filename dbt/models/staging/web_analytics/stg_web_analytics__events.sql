with source as (

    select * from {{ source('web_analytics', 'events') }}

),

cleaned as (

    select
        event_id,
        session_id,
        lower(event_type) as event_type,
        event_timestamp,
        page_url,
        _etl_loaded_at

    from source

)

select * from cleaned
