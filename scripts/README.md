# Scripts

## trigger_dbt_cloud_job.py

Triggers a dbt Cloud job via the [v2 API](https://docs.getdbt.com/dbt-cloud/api-v2-legacy) and polls until the run finishes. Exits 0 on success, 1 on failure or timeout.

### Setup

1. In dbt Cloud, go to **Account Settings → API Tokens** and create a personal access token.
2. Find your `account_id` in the URL (e.g. `https://cloud.getdbt.com/next/accounts/12345/projects/...` — account_id is `12345`).
3. Create the job in dbt Cloud UI and note its `job_id` from the job's URL.

### Run

```bash
pip install requests

export DBT_CLOUD_ACCOUNT_ID=12345
export DBT_CLOUD_JOB_ID=67890
export DBT_CLOUD_API_TOKEN=<your-token>

python scripts/trigger_dbt_cloud_job.py
```

# dbt Cloud Project Setup

dbt Cloud itself is configured in the UI — there's no repo file to commit. Below is what to configure once in the UI:

## 1. Connect the repo

**Settings → Projects → New Project**
- Connect to GitHub and select this repo
- Set the project subdirectory to `dbt/` (since our dbt project is not at the repo root)

## 2. Environments

Create three environments:

| Name | Type | Target Name | Schema |
|------|------|-------------|--------|
| Development | Development | `dev` | `dbt_<user>` |
| CI | Deployment | `ci` | `dbt_ci_pr_<pr_number>` |
| Production | Deployment | `prod` | `prod` |

Wire each environment to its own data warehouse credential set.

## 3. Jobs (per the project spec)

| Job Name | Trigger | Commands | Environment |
|----------|---------|----------|-------------|
| Daily Production Run | Cron `0 6 * * *` | `dbt build --select tag:daily` | Production |
| Weekly Full Refresh | Cron `0 2 * * 0` | `dbt build --full-refresh --exclude tag:daily_only` | Production |
| Snapshot Run | Cron `30 5 * * *` | `dbt snapshot` | Production |
| CI Slim Build | On PR opened/updated | `dbt build --select state:modified+ --defer --state prod` | CI |
| Source Freshness | Cron `0 */2 * * *` | `dbt source freshness` | Production |

## 4. Slack / notifications

**Account Settings → Notifications** — point at a Slack webhook to alert on job failures.
