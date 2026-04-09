-- For completed orders, the order total should match the payment amount
-- This test returns rows where there is a mismatch

with orders as (

    select
        order_id,
        order_total_cents
    from {{ ref('fct_orders') }}
    where order_status = 'completed'
      and payment_status = 'succeeded'

),

payments as (

    select
        order_id,
        sum(amount_cents) as total_payment_cents
    from {{ ref('fct_payments') }}
    where status = 'succeeded'
    group by order_id

),

mismatches as (

    select
        o.order_id,
        o.order_total_cents,
        p.total_payment_cents,
        o.order_total_cents - p.total_payment_cents as difference_cents
    from orders as o
    inner join payments as p
        on o.order_id = p.order_id
    where o.order_total_cents != p.total_payment_cents

)

select * from mismatches