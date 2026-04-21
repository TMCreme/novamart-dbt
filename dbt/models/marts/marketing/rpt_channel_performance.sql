with sessions as (

    select * from {{ ref('fct_sessions') }}

),

attribution as (

    select * from {{ ref('fct_attribution') }}

),

channel_sessions as (

    select
        channel,
        count(*) as session_count,
        count(distinct user_id) as unique_user_count,
        count(case when converted then 1 end) as converted_session_count,
        avg(session_duration_seconds) as avg_session_duration_seconds
    from sessions
    group by channel

),

channel_revenue as (

    select
        attribution_channel as channel,
        count(distinct order_id) as attributed_order_count,
        sum(order_total_dollars) as attributed_revenue_dollars
    from attribution
    group by attribution_channel

),

final as (

    select
        cs.channel,
        cs.session_count,
        cs.unique_user_count,
        cs.converted_session_count,
        cs.avg_session_duration_seconds,
        coalesce(cr.attributed_order_count, 0) as attributed_order_count,
        coalesce(cr.attributed_revenue_dollars, 0) as attributed_revenue_dollars,
        case
            when cs.session_count > 0
            then cast(cs.converted_session_count as float) / cs.session_count
            else 0
        end as conversion_rate

    from channel_sessions as cs
    left join channel_revenue as cr
        on cs.channel = cr.channel

)

select * from final