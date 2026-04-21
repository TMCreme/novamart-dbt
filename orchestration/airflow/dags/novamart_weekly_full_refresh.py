from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator

DBT_PROJECT_PATH = "/opt/airflow/dbt"

default_args = {
    "owner": "analytics-team",
    "retries": 1,
    "retry_delay": timedelta(minutes=10),
    "email_on_failure": False,
}

with DAG(
    dag_id="novamart_weekly_full_refresh",
    description="Weekly full refresh — rebuilds all incremental models from scratch",
    schedule="0 2 * * 0",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=default_args,
    tags=["novamart", "dbt", "weekly", "full-refresh"],
) as dag:

    start = EmptyOperator(task_id="start")

    dbt_seed_full = BashOperator(
        task_id="dbt_seed_full_refresh",
        bash_command=(
            f"cd {DBT_PROJECT_PATH} && "
            "dbt seed --target pg_dev --full-refresh"
        ),
    )

    dbt_run_full = BashOperator(
        task_id="dbt_run_full_refresh",
        bash_command=(
            f"cd {DBT_PROJECT_PATH} && "
            "dbt run --target pg_dev --full-refresh --exclude tag:daily_only"
        ),
    )

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"cd {DBT_PROJECT_PATH} && dbt snapshot --target pg_dev",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_PROJECT_PATH} && dbt test --target pg_dev",
    )

    end = EmptyOperator(task_id="end")

    start >> dbt_seed_full >> dbt_run_full >> dbt_snapshot >> dbt_test >> end
