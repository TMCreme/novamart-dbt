{{
    config(
        materialized='incremental',
        unique_key='session_id',
        incremental_strategy='delete+insert'
    )
}}

with sessions as (

    select * from {{ ref('int_sessions_mapped_to_users') }}

),

events_summary as (

    select
        session_id,
        count(*) as event_count,
        count(case when event_type = 'page_view' then 1 end) as page_view_count,
        count(case when event_type = 'product_click' then 1 end) as product_click_count,
        count(case when event_type = 'add_to_cart' then 1 end) as add_to_cart_count,
        count(case when event_type = 'checkout' then 1 end) as checkout_count,
        count(case when event_type = 'purchase' then 1 end) as purchase_count
    from {{ ref('stg_web_analytics__events') }}
    group by session_id

),

final as (

    select
        s.session_id,
        s.user_id,
        s.user_name,
        s.user_email,
        s.user_tier,
        s.session_start,
        s.session_end,
        s.session_duration_seconds,
        s.device_type,
        s.channel,
        s.landing_page,
        s.is_anonymous,

        coalesce(e.event_count, 0) as event_count,
        coalesce(e.page_view_count, 0) as page_view_count,
        coalesce(e.product_click_count, 0) as product_click_count,
        coalesce(e.add_to_cart_count, 0) as add_to_cart_count,
        coalesce(e.checkout_count, 0) as checkout_count,
        coalesce(e.purchase_count, 0) as purchase_count,
        case when coalesce(e.purchase_count, 0) > 0 then true else false end as converted

    from sessions as s
    left join events_summary as e
        on s.session_id = e.session_id

    {% if is_incremental() %}
        where s.session_start >= (
            select max(session_start) - interval '24 hours'
            from {{ this }}
        )
    {% endif %}

)

select * from final