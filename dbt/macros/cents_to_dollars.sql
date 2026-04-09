{% macro cents_to_dollars(column_name) %}
    ({{ column_name }} / 100.0)::numeric(12,2)
{% endmacro %}