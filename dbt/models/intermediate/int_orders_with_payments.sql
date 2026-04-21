{{
    config(
        materialized='table'
    )
}}

with orders as (

    select * from {{ ref('stg_shopify__orders') }}

),

payments as (

    select * from {{ ref('stg_stripe__payments') }}

),

order_items_summary as (

    select
        order_id,
        count(*) as item_count,
        sum(quantity) as total_quantity,
        sum(unit_price_cents * quantity) as calculated_total_cents,
        sum(unit_price_dollars * quantity) as calculated_total_dollars
    from {{ ref('stg_shopify__order_items') }}
    group by order_id

),

orders_with_payments as (

    select
        o.order_id,
        o.customer_id,
        o.order_date,
        o.status as order_status,
        o.total_amount_cents as order_total_cents,
        o.total_amount_dollars as order_total_dollars,
        o.shipping_address_id,
        o.order_updated_at,

        oi.item_count,
        oi.total_quantity,
        oi.calculated_total_cents,
        oi.calculated_total_dollars,

        p.payment_id,
        p.amount_cents as payment_amount_cents,
        p.amount_dollars as payment_amount_dollars,
        p.currency as payment_currency,
        p.status as payment_status,
        p.payment_method,
        p.created_at as payment_created_at

    from orders as o
    left join order_items_summary as oi
        on o.order_id = oi.order_id
    left join payments as p
        on o.order_id = p.order_id

)

select * from orders_with_payments
