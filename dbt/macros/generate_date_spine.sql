{% macro generate_date_spine(start_date, end_date) %}
    {% if target.type == 'snowflake' %}
        select
            dateadd(day, row_number() over (order by 1) - 1, '{{ start_date }}'::date) as date_day
        from table(generator(rowcount => datediff(day, '{{ start_date }}'::date, '{{ end_date }}'::date) + 1))
    {% else %}
        {# DuckDB and PostgreSQL both support generate_series #}
        select
            date_day::date as date_day
        from generate_series('{{ start_date }}'::date, '{{ end_date }}'::date, interval '1 day') as t(date_day)
    {% endif %}
{% endmacro %}