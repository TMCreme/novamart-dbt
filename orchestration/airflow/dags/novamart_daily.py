from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from cosmos import DbtDag, DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig
from cosmos.profiles import PostgresUserPasswordProfileMapping

DBT_PROJECT_PATH = Path("/opt/airflow/dbt")

profile_config = ProfileConfig(
    profile_name="novamart",
    target_name="pg_dev",
    profile_mapping=PostgresUserPasswordProfileMapping(
        conn_id="postgres_novamart",
        profile_args={
            "schema": "prod",
            "threads": 4,
        },
    ),
)

default_args = {
    "owner": "analytics-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="novamart_daily",
    description="Daily NovaMart dbt pipeline — staging through marts with snapshots",
    schedule="0 6 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=default_args,
    tags=["novamart", "dbt", "daily"],
) as dag:

    start = EmptyOperator(task_id="start")

    source_freshness = BashOperator(
        task_id="source_freshness",
        bash_command=(
            "cd /opt/airflow/dbt && "
            "dbt source freshness --target pg_dev || true"
        ),
    )

    dbt_seed = BashOperator(
        task_id="dbt_seed",
        bash_command="cd /opt/airflow/dbt && dbt seed --target pg_dev --select tag:daily",
    )

    transform = DbtTaskGroup(
        group_id="transform",
        project_config=ProjectConfig(DBT_PROJECT_PATH),
        profile_config=profile_config,
        execution_config=ExecutionConfig(
            dbt_executable_path="/home/airflow/.local/bin/dbt",
        ),
        render_config={
            "select": ["tag:daily"],
        },
    )

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command="cd /opt/airflow/dbt && dbt snapshot --target pg_dev",
    )

    dbt_test_critical = BashOperator(
        task_id="dbt_test_critical",
        bash_command=(
            "cd /opt/airflow/dbt && "
            "dbt test --target pg_dev --select config.severity:error"
        ),
    )

    log_run_metadata = BashOperator(
        task_id="log_run_metadata",
        bash_command=(
            "cd /opt/airflow/dbt && "
            "dbt run-operation log_run_metadata --target pg_dev"
        ),
    )

    end = EmptyOperator(task_id="end", trigger_rule="none_failed_min_one_success")

    start >> source_freshness >> dbt_seed >> transform >> dbt_snapshot >> dbt_test_critical >> log_run_metadata >> end
