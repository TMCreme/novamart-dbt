with source as (

    select * from {{ source('web_analytics', 'page_views') }}

),

cleaned as (

    select
        page_view_id,
        session_id,
        page_url,
        view_timestamp,
        duration_seconds,
        _etl_loaded_at

    from source

)

select * from cleaned