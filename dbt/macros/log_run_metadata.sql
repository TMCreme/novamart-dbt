{% macro log_run_metadata() %}

    {% if execute and flags.WHICH in ('run', 'build') %}

        {% set audit_table = target.schema ~ '.dbt_run_audit' %}

        {% set create_table_sql %}
            create table if not exists {{ audit_table }} (
                invocation_id varchar,
                run_started_at timestamp,
                run_completed_at timestamp,
                target_name varchar,
                model_count integer,
                test_count integer,
                status varchar
            )
        {% endset %}

        {% do run_query(create_table_sql) %}

        {% set model_count = results | selectattr('node.resource_type', 'equalto', 'model') | list | length %}
        {% set test_count = results | selectattr('node.resource_type', 'equalto', 'test') | list | length %}
        {% set failed_results = results | selectattr('status', 'in', ['error', 'fail']) | list %}
        {% set status = 'error' if failed_results | length > 0 else 'success' %}

        {% set insert_sql %}
            insert into {{ audit_table }} (
                invocation_id,
                run_started_at,
                run_completed_at,
                target_name,
                model_count,
                test_count,
                status
            )
            values (
                '{{ invocation_id }}',
                '{{ run_started_at }}',
                current_timestamp,
                '{{ target.name }}',
                {{ model_count }},
                {{ test_count }},
                '{{ status }}'
            )
        {% endset %}

        {% do run_query(insert_sql) %}

        {{ log("Logged run metadata: " ~ model_count ~ " models, " ~ test_count ~ " tests, status=" ~ status, info=true) }}

    {% endif %}

{% endmacro %}