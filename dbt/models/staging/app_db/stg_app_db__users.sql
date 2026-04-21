with source as (

    select * from {{ source('app_db', 'users') }}

),

cleaned as (

    select
        user_id,
        email,
        name as full_name,
        lower(tier) as tier,
        created_at,
        updated_at,
        _etl_loaded_at

    from source
    where is_deleted = false

)

select * from cleaned
