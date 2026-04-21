with source as (

    select * from {{ source('shopify', 'order_items') }}

),

cleaned as (

    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price_cents,
        {{ cents_to_dollars('unit_price_cents') }} as unit_price_dollars,
        _etl_loaded_at

    from source

)

select * from cleaned
