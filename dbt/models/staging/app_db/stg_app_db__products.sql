with source as (

    select * from {{ source('app_db', 'products') }}

),

cleaned as (

    select
        product_id,
        name as product_name,
        lower(category) as category,
        price_cents,
        {{ cents_to_dollars('price_cents') }} as price_dollars,
        created_at,
        updated_at,
        _etl_loaded_at

    from source
    where is_deleted = false

)

select * from cleaned