{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {#
        Schema routing logic:

        - In production (target.name = prod, pg_prod, or snowflake_prod):
          Use the custom schema literally — models go to dedicated schemas
          like `staging`, `marts_core`, `snapshots`, etc.

        - In dev / CI / everything else:
          Prefix the custom schema with the target schema so each
          developer or CI run gets an isolated copy
          (e.g., `dbt_cloud_pr_123_marts_core`, `dev_marts_core`).

        - No custom schema specified:
          Fall back to target schema as-is.
    #}

    {%- set prod_targets = ['prod', 'pg_prod', 'snowflake_prod'] -%}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name in prod_targets -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}