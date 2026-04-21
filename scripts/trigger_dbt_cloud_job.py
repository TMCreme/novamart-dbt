"""Trigger a dbt Cloud job and poll until completion.

Usage:
    export DBT_CLOUD_ACCOUNT_ID=12345
    export DBT_CLOUD_JOB_ID=67890
    export DBT_CLOUD_API_TOKEN=<your-token>
    python scripts/trigger_dbt_cloud_job.py

Exits 0 on success, 1 on failure or timeout.
"""

from __future__ import annotations

import os
import sys
import time
from typing import Any

import requests

API_BASE = "https://cloud.getdbt.com/api/v2"
POLL_INTERVAL_SECONDS = 15
TIMEOUT_SECONDS = 60 * 60

RUN_STATUS = {
    1: "queued",
    2: "starting",
    3: "running",
    10: "success",
    20: "error",
    30: "cancelled",
}
TERMINAL_STATUSES = {10, 20, 30}


def _env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required env var: {name}")
    return value


def trigger_job(account_id: str, job_id: str, token: str, cause: str) -> dict[str, Any]:
    url = f"{API_BASE}/accounts/{account_id}/jobs/{job_id}/run/"
    response = requests.post(
        url,
        headers={"Authorization": f"Token {token}"},
        json={"cause": cause},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["data"]


def get_run(account_id: str, run_id: int, token: str) -> dict[str, Any]:
    url = f"{API_BASE}/accounts/{account_id}/runs/{run_id}/"
    response = requests.get(
        url,
        headers={"Authorization": f"Token {token}"},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["data"]


def main() -> int:
    account_id = _env("DBT_CLOUD_ACCOUNT_ID")
    job_id = _env("DBT_CLOUD_JOB_ID")
    token = _env("DBT_CLOUD_API_TOKEN")
    cause = os.environ.get("DBT_CLOUD_CAUSE", "Triggered via CLI script")

    print(f"Triggering dbt Cloud job {job_id} on account {account_id}")
    run = trigger_job(account_id, job_id, token, cause)
    run_id = run["id"]
    print(f"Run {run_id} queued — polling every {POLL_INTERVAL_SECONDS}s")

    elapsed = 0
    while elapsed < TIMEOUT_SECONDS:
        run = get_run(account_id, run_id, token)
        status = run["status"]
        status_name = RUN_STATUS.get(status, f"unknown({status})")
        print(f"[{elapsed}s] status={status_name}")

        if status in TERMINAL_STATUSES:
            if status == 10:
                print(f"Run {run_id} succeeded")
                return 0
            print(f"Run {run_id} ended with status={status_name}")
            print(f"View at: https://cloud.getdbt.com/accounts/{account_id}/runs/{run_id}")
            return 1

        time.sleep(POLL_INTERVAL_SECONDS)
        elapsed += POLL_INTERVAL_SECONDS

    print(f"Timed out after {TIMEOUT_SECONDS}s")
    return 1


if __name__ == "__main__":
    sys.exit(main())
