{{
    config(
        materialized='incremental',
        unique_key='payment_id',
        incremental_strategy='delete+insert'
    )
}}

with payments as (

    select * from {{ ref('stg_stripe__payments') }}

),

final as (

    select
        payment_id,
        order_id,
        amount_cents,
        amount_dollars,
        currency,
        status,
        payment_method,
        created_at

    from payments

    {% if is_incremental() %}
        where payment_id not in (select payment_id from {{ this }})
    {% endif %}

)

select * from final
