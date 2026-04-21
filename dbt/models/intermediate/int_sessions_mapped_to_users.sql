with sessions as (

    select * from {{ ref('stg_web_analytics__sessions') }}

),

users as (

    select * from {{ ref('stg_app_db__users') }}

),

mapped as (

    select
        s.session_id,
        s.user_id,
        u.full_name as user_name,
        u.email as user_email,
        u.tier as user_tier,
        s.session_start,
        s.session_end,
        s.device_type,
        s.channel,
        s.landing_page,
        case
            when s.user_id is not null then false
            else true
        end as is_anonymous,
        extract(epoch from (s.session_end - s.session_start)) as session_duration_seconds

    from sessions as s
    left join users as u
        on s.user_id = u.user_id

)

select * from mapped
