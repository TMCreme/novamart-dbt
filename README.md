# NovaMart Analytics Platform

A production-grade dbt analytics platform for **NovaMart**, a fictional direct-to-consumer e-commerce company. The project ingests data from four operational sources, transforms it through a layered model architecture, and serves clean datasets to downstream consumers.

## Architecture

```
seeds ──► staging ──► intermediate ──► marts/core ──► marts/finance
                                          │               │
                                          │          marts/marketing
                                          │
                                          ▼
                                      snapshots
                                          │
                                          ▼
                                      exposures
```

### Source Systems

| Source | Key Entities | Behavior |
|--------|-------------|----------|
| `app_db` | users, products, inventory, addresses | Mutable rows, soft deletes |
| `shopify` | orders, order_items, refunds | Append-mostly, late-arriving rows (up to 72h) |
| `stripe` | payments, charges, refunds, disputes | Event-sourced, immutable append |
| `web_analytics` | sessions, events, page_views | High volume, sessionized, nullable user_ids |

### Model Layers

| Layer | Materialization | Purpose |
|-------|----------------|---------|
| `staging` | view | 1:1 source cleaning — rename, cast, filter deleted |
| `intermediate` | ephemeral | Cross-source joins, dedup, business logic |
| `marts/dim_*` | table | Conformed dimensions |
| `marts/fct_*` | incremental | Business facts at defined grain |
| `marts/rpt_*` | table | Aggregated reporting tables |
| `snapshots` | snapshot (SCD2) | Slowly changing dimension history |

## Prerequisites

- Python 3.11+
- One or more of:
  - **DuckDB** (default, zero setup): `pip install dbt-duckdb`
  - **PostgreSQL**: Docker, `pip install dbt-postgres`
  - **Snowflake**: Trial account, `pip install dbt-snowflake`

## Quick Start

```bash
# Clone and install
git clone <repo-url> && cd novamart
pip install dbt-duckdb  # or dbt-postgres / dbt-snowflake

# Run with DuckDB (default target)
cd dbt
dbt deps
dbt seed
dbt build

# Run with PostgreSQL
cd ../infra && docker compose up -d
cd ../dbt
export NOVAMART_PG_PASSWORD=localdev
dbt build --target pg_dev

# Run with Snowflake
export SNOWFLAKE_ACCOUNT=<account>
export SNOWFLAKE_USER=<user>
export SNOWFLAKE_PASSWORD=<password>
dbt build --target snowflake_dev
```

## Project Structure

```
novamart/
├── dbt/                          # dbt project (all 3 warehouses via profiles)
│   ├── dbt_project.yml
│   ├── profiles.yml              # dev (DuckDB), pg_*, snowflake_* targets
│   ├── packages.yml              # dbt_utils, dbt_expectations, codegen
│   ├── selectors.yml             # daily_build, ci_slim, finance_only
│   ├── .sqlfluff                 # SQL linter config
│   ├── models/
│   │   ├── staging/              # 1:1 source cleaning
│   │   ├── intermediate/         # Cross-source joins
│   │   └── marts/                # Business-consumable facts & dims
│   │       ├── core/
│   │       ├── finance/
│   │       └── marketing/
│   ├── seeds/                    # CSV fixtures per source
│   ├── snapshots/                # SCD Type 2 tracking
│   ├── macros/                   # Reusable Jinja SQL
│   ├── tests/
│   │   ├── generic/              # Reusable test definitions
│   │   └── singular/             # One-off business assertions
│   └── analyses/                 # Ad-hoc investigative queries
├── orchestration/
│   └── airflow/dags/             # Airflow DAG definitions
├── infra/
│   ├── docker-compose.yml        # PostgreSQL 15 local instance
│   └── init.sql                  # Roles, schemas, default grants
├── scripts/                      # Utility scripts (e.g. dbt Cloud API trigger)
├── .github/workflows/
│   └── dbt_ci.yml                # Slim CI on pull requests
└── docs/
    └── spec.md                   # Full project specification
```

## Orchestration

Two orchestration options are supported independently:

- **Apache Airflow** — DAGs in `orchestration/airflow/dags/` using [Astronomer Cosmos](https://astronomer.github.io/astronomer-cosmos/) to auto-generate tasks from the dbt DAG.
- **dbt Cloud** — configured via the dbt Cloud UI. A Python API trigger script lives in `scripts/`.

## Testing

The project follows a test-driven development approach. Every model requires:

- `unique` + `not_null` on primary key
- At least one business-logic test (singular or unit test)
- All tests pass before a model is considered complete

```bash
cd dbt

# Run all tests
dbt test

# Run tests for a specific model
dbt test --select fct_orders

# Run only unit tests
dbt test --select test_type:unit

# Check source freshness
dbt source freshness
```

## Linting

```bash
cd dbt

# Lint SQL
sqlfluff lint models/

# Auto-fix lint violations
sqlfluff fix models/
```

## CI/CD

Pull requests to `develop` or `main` trigger a GitHub Actions workflow that:

1. Lints SQL with sqlfluff
2. Runs `dbt seed` against a CI PostgreSQL instance
3. Runs a slim build (`state:modified+`) to test only what changed
