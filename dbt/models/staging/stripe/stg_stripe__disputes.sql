with source as (

    select * from {{ source('stripe', 'disputes') }}

),

cleaned as (

    select
        dispute_id,
        charge_id,
        amount_cents,
        {{ cents_to_dollars('amount_cents') }} as amount_dollars,
        reason,
        lower(status) as status,
        created_at,
        _etl_loaded_at

    from source

)

select * from cleaned
