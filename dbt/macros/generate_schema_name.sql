{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {#
        If no custom schema is specified in the model config, fall back to the target schema.
        If a custom schema IS specified, use it literally (no `<target>_<custom>` prefix).
        This lets us route layers to dedicated schemas (`staging`, `marts_core`,
        `snapshots`, `raw_app_db`, etc.) as defined in infra/init.sql.
    #}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}