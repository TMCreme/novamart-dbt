# NovaMart Airflow Orchestration

Local Airflow setup for orchestrating the NovaMart dbt pipeline. Uses [Astronomer Cosmos](https://astronomer.github.io/astronomer-cosmos/) to auto-generate Airflow tasks from the dbt DAG.

## Prerequisites

- Docker Desktop running
- The NovaMart Postgres container from `infra/` must be running and reachable on `localhost:5493`
- The `dev` (or `prod`) schema populated from at least one manual `dbt seed`/`dbt run`

## Start Airflow

From this directory:

```bash
mkdir -p logs plugins
export AIRFLOW_UID=$(id -u)
docker compose up -d
```

Wait ~60 seconds for all services to initialize. The web UI is at <http://localhost:8080> — login with `admin` / `admin`.

## Configure the Postgres connection

In the Airflow UI: **Admin → Connections → Add**

| Field | Value |
|-------|-------|
| Conn Id | `postgres_novamart` |
| Conn Type | Postgres |
| Host | `host.docker.internal` |
| Schema | `novamart` |
| Login | `novamart_loader` |
| Password | `localdev` |
| Port | `5493` |

(Using `host.docker.internal` so the Airflow container can reach the Postgres container in the separate `novamart-airflow` network — if you put both in the same Docker network, use the service name instead.)

## DAGs

| DAG | Schedule | Purpose |
|-----|----------|---------|
| `novamart_daily` | `0 6 * * *` (daily 06:00 UTC) | Seed tagged-as-daily, transform via Cosmos, snapshot, critical tests |
| `novamart_weekly_full_refresh` | `0 2 * * 0` (Sunday 02:00 UTC) | Drops incrementals and rebuilds from scratch |

Unpause DAGs in the UI to activate them.

## Stop Airflow

```bash
docker compose down
```

To wipe the Airflow metadata DB as well:

```bash
docker compose down -v
```
