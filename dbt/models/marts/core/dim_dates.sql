with date_spine as (

    {{ generate_date_spine('2023-01-01', '2025-12-31') }}

),

dates as (

    select
        date_day,
        extract(year from date_day) as year,
        extract(month from date_day) as month,
        extract(day from date_day) as day_of_month,
        extract(dow from date_day) as day_of_week,
        extract(quarter from date_day) as quarter,
        extract(week from date_day) as week_of_year,
        case
            when extract(dow from date_day) in (0, 6) then true
            else false
        end as is_weekend

    from date_spine

)

select * from dates
