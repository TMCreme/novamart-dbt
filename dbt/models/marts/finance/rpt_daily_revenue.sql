with orders as (

    select * from {{ ref('fct_orders') }}
    where order_status = 'completed'

),

refunds as (

    select * from {{ ref('fct_refunds') }}
    where source_system = 'shopify'

),

daily_orders as (

    select
        cast(order_date as date) as revenue_date,
        count(*) as order_count,
        count(distinct customer_id) as unique_customer_count,
        sum(order_total_dollars) as gross_revenue_dollars,
        sum(total_quantity) as total_items_sold

    from orders
    group by cast(order_date as date)

),

daily_refunds as (

    select
        cast(refunded_at as date) as revenue_date,
        count(*) as refund_count,
        sum(refund_amount_dollars) as total_refund_dollars
    from refunds
    group by cast(refunded_at as date)

),

final as (

    select
        d.date_day as revenue_date,
        coalesce(o.order_count, 0) as order_count,
        coalesce(o.unique_customer_count, 0) as unique_customer_count,
        coalesce(o.gross_revenue_dollars, 0) as gross_revenue_dollars,
        coalesce(o.total_items_sold, 0) as total_items_sold,
        coalesce(r.refund_count, 0) as refund_count,
        coalesce(r.total_refund_dollars, 0) as total_refund_dollars,
        coalesce(o.gross_revenue_dollars, 0) - coalesce(r.total_refund_dollars, 0) as net_revenue_dollars

    from {{ ref('dim_dates') }} as d
    left join daily_orders as o
        on d.date_day = o.revenue_date
    left join daily_refunds as r
        on d.date_day = r.revenue_date
    where
        d.date_day between
        (select min(order_date)::date from orders)
        and (select max(order_date)::date from orders)

)

select * from final
