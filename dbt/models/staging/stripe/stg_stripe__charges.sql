with source as (

    select * from {{ source('stripe', 'charges') }}

),

cleaned as (

    select
        charge_id,
        payment_id,
        amount_cents,
        {{ cents_to_dollars('amount_cents') }} as amount_dollars,
        lower(currency) as currency,
        lower(status) as status,
        created_at,
        _etl_loaded_at

    from source

)

select * from cleaned