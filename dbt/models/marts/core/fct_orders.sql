{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='delete+insert',
        on_schema_change='sync_all_columns'
    )
}}

with orders_with_payments as (

    select * from {{ ref('int_orders_with_payments') }}

),

final as (

    select
        order_id,
        customer_id,
        order_date,
        order_status,
        order_total_cents,
        order_total_dollars,
        shipping_address_id,
        order_updated_at,

        item_count,
        total_quantity,
        calculated_total_cents,
        calculated_total_dollars,

        payment_id,
        payment_amount_cents,
        payment_amount_dollars,
        payment_currency,
        payment_status,
        payment_method,
        payment_created_at

    from orders_with_payments

    {% if is_incremental() %}
        where order_updated_at >= (
            select max(order_updated_at) - interval '{{ var("lookback_window_hours") }} hours'
            from {{ this }}
        )
    {% endif %}

)

select * from final