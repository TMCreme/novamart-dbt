{% macro union_sources(schema_pattern, table_name) %}
    {%- set relations = dbt_utils.get_relations_by_pattern(
        schema_pattern=schema_pattern,
        table_pattern=table_name
    ) -%}

    {%- if relations | length == 0 -%}
        {{ exceptions.raise_compiler_error("No relations found matching schema pattern '" ~ schema_pattern ~ "' and table '" ~ table_name ~ "'") }}
    {%- endif -%}

    {%- for relation in relations %}
        select
            *,
            '{{ relation.schema }}' as _source_schema
        from {{ relation }}
        {%- if not loop.last %} union all {% endif -%}
    {%- endfor %}
{% endmacro %}