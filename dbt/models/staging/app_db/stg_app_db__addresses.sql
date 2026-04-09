with source as (

    select * from {{ source('app_db', 'addresses') }}

),

cleaned as (

    select
        address_id,
        user_id,
        street,
        city,
        state,
        zip,
        upper(country) as country,
        is_default,
        _etl_loaded_at

    from source

)

select * from cleaned