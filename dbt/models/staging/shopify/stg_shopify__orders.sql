with source as (

    select * from {{ source('shopify', 'orders') }}

),

cleaned as (

    select
        order_id,
        customer_id,
        order_date,
        lower(status) as status,
        total_amount_cents,
        {{ cents_to_dollars('total_amount_cents') }} as total_amount_dollars,
        shipping_address_id,
        order_updated_at,
        _etl_loaded_at

    from source

)

select * from cleaned