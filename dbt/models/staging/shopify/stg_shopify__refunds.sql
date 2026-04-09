with source as (

    select * from {{ source('shopify', 'refunds') }}

),

cleaned as (

    select
        refund_id,
        order_id,
        reason,
        refund_amount_cents,
        {{ cents_to_dollars('refund_amount_cents') }} as refund_amount_dollars,
        refunded_at,
        _etl_loaded_at

    from source

)

select * from cleaned