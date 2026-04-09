with source as (

    select * from {{ source('stripe', 'payments') }}

),

cleaned as (

    select
        payment_id,
        order_id,
        amount_cents,
        {{ cents_to_dollars('amount_cents') }} as amount_dollars,
        lower(currency) as currency,
        lower(status) as status,
        lower(payment_method) as payment_method,
        created_at,
        _etl_loaded_at

    from source

)

select * from cleaned