with users as (

    select * from {{ ref('stg_app_db__users') }}

),

addresses as (

    select * from {{ ref('stg_app_db__addresses') }}
    where is_default = true

),

orders as (

    select
        customer_id,
        count(*) as lifetime_order_count,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        sum(total_amount_dollars) as lifetime_spend_dollars
    from {{ ref('stg_shopify__orders') }}
    where status = 'completed'
    group by customer_id

),

customers as (

    select
        {{ generate_surrogate_key(['u.user_id']) }} as customer_key,
        u.user_id,
        u.full_name,
        u.email,
        u.tier,
        u.created_at as customer_created_at,

        a.street,
        a.city,
        a.state,
        a.zip,
        a.country,

        coalesce(o.lifetime_order_count, 0) as lifetime_order_count,
        o.first_order_date,
        o.last_order_date,
        coalesce(o.lifetime_spend_dollars, 0) as lifetime_spend_dollars

    from users as u
    left join addresses as a
        on u.user_id = a.user_id
    left join orders as o
        on u.user_id = o.customer_id

)

select * from customers