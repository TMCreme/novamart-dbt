with source as (

    select * from {{ source('web_analytics', 'sessions') }}

),

cleaned as (

    select
        session_id,
        user_id,
        session_start,
        session_end,
        lower(device_type) as device_type,
        lower(channel) as channel,
        landing_page,
        _etl_loaded_at

    from source

)

select * from cleaned