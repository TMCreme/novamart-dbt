with source as (

    select * from {{ source('app_db', 'inventory') }}

),

cleaned as (

    select
        inventory_id,
        product_id,
        warehouse_location,
        quantity,
        updated_at,
        _etl_loaded_at

    from source

)

select * from cleaned
