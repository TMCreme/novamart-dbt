with converted_sessions as (

    select
        session_id,
        user_id,
        session_start,
        channel,
        landing_page
    from {{ ref('fct_sessions') }}
    where
        converted = true
        and user_id is not null

),

orders as (

    select
        order_id,
        customer_id,
        order_date,
        order_total_dollars
    from {{ ref('fct_orders') }}
    where order_status = 'completed'

),

sessions_before_order as (

    select
        o.order_id,
        o.customer_id,
        o.order_date,
        o.order_total_dollars,
        s.session_id,
        s.channel,
        s.landing_page,
        s.session_start,
        row_number() over (
            partition by o.order_id
            order by s.session_start desc
        ) as recency_rank

    from orders as o
    left join converted_sessions as s
        on
            o.customer_id = s.user_id
            and s.session_start <= o.order_date

),

last_touch as (

    select
        order_id,
        customer_id,
        order_date,
        order_total_dollars,
        session_id as attribution_session_id,
        channel as attribution_channel,
        landing_page as attribution_landing_page,
        session_start as attribution_session_start

    from sessions_before_order
    where recency_rank = 1

)

select * from last_touch
