{% macro grant_select(role_name) %}
    {% if target.type != 'duckdb' %}
        grant select on {{ this }} to {{ role_name }};
    {% endif %}
{% endmacro %}