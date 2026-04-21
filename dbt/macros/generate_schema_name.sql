{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {#
        Schema routing logic:

        - In production (detected via target.name OR the dbt Cloud environment name):
          Use the custom schema literally (e.g., `marts_core`, `staging`).

        - In dev / CI / everything else:
          Prefix the custom schema with the target schema so each developer
          or CI run gets an isolated copy
          (e.g., `dbt_cloud_pr_123_marts_core`, `dev_marts_core`).

        - No custom schema specified:
          Fall back to the target schema as-is.

        We detect production via three signals for robustness across dbt Cloud,
        local CLI, and Airflow:
          1. target.name in a known prod list
          2. DBT_CLOUD_ENVIRONMENT_NAME = "Production" (dbt Cloud sets this)
          3. DBT_ENV = "prod" (conventional env var for local/Airflow)
    #}

    {%- set prod_targets = ['prod', 'pg_prod', 'snowflake_prod'] -%}
    {%- set dbt_cloud_env = env_var('DBT_CLOUD_ENVIRONMENT_NAME', '') | lower -%}
    {%- set env_flag = env_var('DBT_ENV', '') | lower -%}

    {%- set is_prod = (
        target.name in prod_targets
        or dbt_cloud_env == 'production'
        or env_flag == 'prod'
    ) -%}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif is_prod -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}