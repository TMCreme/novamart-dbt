# Project Specification: Multi-Source E-Commerce Analytics Platform (dbt)

## Document Meta

| Field             | Value                                      |
|-------------------|--------------------------------------------|
| Version           | 1.0                                        |
| Status            | Draft                                      |
| Target Warehouses | PostgreSQL 15+, Snowflake, DuckDB 0.10+    |
| Orchestration     | Apache Airflow 2.x, dbt Cloud              |
| dbt Version       | dbt-core 1.8+                              |
| Methodology       | Test-Driven Development (TDD)              |

---

## 1. Project Vision & Learning Objectives

### 1.1 Vision

Build a production-grade dbt analytics platform for a fictional e-commerce company, **"NovaMart"**, that ingests data from four operational sources, transforms it through a layered model architecture, and serves clean datasets to downstream consumers. The project is intentionally designed to exercise every advanced dbt feature in a realistic context.

### 1.2 Learning Objectives (mapped to deliverables)

| # | Objective                                    | Where You'll Learn It            |
|---|----------------------------------------------|----------------------------------|
| 1 | Source configuration & freshness             | Phase 1 — Staging layer          |
| 2 | Jinja macros & DRY SQL                       | Phase 1 — `union_sources` macro  |
| 3 | Incremental models (merge, delete+insert)    | Phase 2 — `fct_orders`           |
| 4 | Snapshots & SCD Type 2                       | Phase 2 — `snap_customers`       |
| 5 | Custom generic & singular tests              | Every phase (TDD)                |
| 6 | `dbt_expectations` data quality suite        | Phase 3 — quality layer          |
| 7 | Packages (`dbt_utils`, `codegen`)            | Phase 1 onward                   |
| 8 | Exposures & semantic / metrics layer         | Phase 4                          |
| 9 | Pre/post hooks & operations                  | Phase 3 — audit logging          |
| 10| Tags, selectors & slim CI                    | Phase 5 — CI/CD                  |
| 11| Multi-environment config (dev/stg/prod)      | Phase 5                          |
| 12| Orchestration (Airflow & dbt Cloud)          | Phase 6                          |
| 13| Cross-database macros & warehouse-specific SQL| Throughout — adapter awareness   |

---

## 2. Fictional Domain: NovaMart

### 2.1 Business Context

NovaMart is a direct-to-consumer e-commerce company selling electronics and lifestyle goods. They operate:

- A **web storefront** (Shopify-like order system)
- **Stripe** for payment processing
- A **PostgreSQL application database** for user accounts, product catalog, and inventory
- **Google Analytics** style event tracking for web sessions and marketing attribution

### 2.2 Source Systems

| Source           | Simulated As            | Key Entities                                   | Behavior Characteristics                          |
|------------------|-------------------------|-------------------------------------------------|---------------------------------------------------|
| `app_db`         | Seed CSV + raw tables   | `users`, `products`, `inventory`, `addresses`   | Mutable rows (updates in place), soft deletes     |
| `shopify`        | Seed CSV + raw tables   | `orders`, `order_items`, `refunds`              | Append-mostly, late-arriving rows (up to 72h)     |
| `stripe`         | Seed CSV + raw tables   | `payments`, `charges`, `refunds`, `disputes`    | Event-sourced, immutable append                   |
| `web_analytics`  | Seed CSV + raw tables   | `sessions`, `events`, `page_views`              | High volume, sessionized, nullable user_ids       |

### 2.3 Seed Data Design

Each source will have two seed files:

- **`_initial.csv`** — the starting state (loaded in Phase 1).
- **`_incremental.csv`** — additional/changed rows added later to exercise incremental models, snapshots, and late-arriving data handling.

Seed data will include intentional quality issues for testing: nulls in non-nullable business fields, duplicate keys, negative amounts, future-dated timestamps, orphaned foreign keys.

---

## 3. Architecture Overview

### 3.1 Layer Model

```
seeds/                  Raw CSV fixtures simulating source extracts
  ├── app_db/
  ├── shopify/
  ├── stripe/
  └── web_analytics/

models/
  ├── staging/          1:1 source cleaning — rename, cast, filter deleted
  │   ├── app_db/
  │   ├── shopify/
  │   ├── stripe/
  │   └── web_analytics/
  │
  ├── intermediate/     Cross-source joins, dedup, business logic
  │   ├── int_orders_with_payments.sql
  │   ├── int_sessions_mapped_to_users.sql
  │   └── int_product_inventory_current.sql
  │
  └── marts/            Business-consumable facts and dimensions
      ├── core/
      │   ├── dim_customers.sql
      │   ├── dim_products.sql
      │   ├── dim_dates.sql          (generated via macro)
      │   └── fct_orders.sql         (incremental)
      │
      ├── finance/
      │   ├── fct_payments.sql       (incremental)
      │   ├── fct_refunds.sql
      │   └── rpt_daily_revenue.sql
      │
      └── marketing/
          ├── fct_sessions.sql       (incremental)
          ├── fct_attribution.sql
          └── rpt_channel_performance.sql

snapshots/
  ├── snap_customers.sql             SCD Type 2
  └── snap_products.sql              SCD Type 2

macros/
  ├── generate_surrogate_key.sql
  ├── union_sources.sql
  ├── cents_to_dollars.sql
  ├── generate_date_spine.sql
  ├── grant_select.sql               (hook helper)
  └── log_run_metadata.sql           (audit operation)

tests/
  ├── generic/
  │   ├── test_not_negative.sql
  │   ├── test_valid_currency_code.sql
  │   └── test_referential_integrity.sql
  └── singular/
      ├── assert_revenue_reconciles_with_payments.sql
      ├── assert_no_orphaned_order_items.sql
      └── assert_session_duration_within_bounds.sql

analyses/
  ├── investigate_late_arriving_orders.sql
  └── cohort_revenue_check.sql
```

### 3.2 Model Materialization Strategy

| Layer          | Default Materialization | Exceptions                                              |
|----------------|------------------------|---------------------------------------------------------|
| `staging`      | `view`                 | High-volume `stg_web_analytics__events` → `ephemeral`   |
| `intermediate` | `ephemeral`            | `int_orders_with_payments` → `table` (heavy join)        |
| `marts/dim_*`  | `table`                | —                                                        |
| `marts/fct_*`  | `incremental`          | `fct_refunds` → `table` (low volume)                    |
| `marts/rpt_*`  | `table`                | —                                                        |
| `snapshots`    | `snapshot` (SCD2)      | —                                                        |

### 3.3 DAG Overview (dependency flow)

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

---

## 4. Warehouse-Specific Specifications

Each warehouse target is an independent variant of the project. You will build one at a time (recommended order: DuckDB → PostgreSQL → Snowflake) and learn how dbt adapts across engines.

---

### 4.1 DuckDB Variant

**Purpose:** Fastest feedback loop. Zero infrastructure. Ideal for the TDD workflow — run full builds in seconds.

**Adapter:** `dbt-duckdb` 1.8+

**Setup:**
- Single file database: `novamart.duckdb` in project root.
- `profiles.yml` points to a local file path, no credentials needed.
- All models run in-process.

**Warehouse-specific considerations:**

| Concern                  | DuckDB Approach                                                                                      |
|--------------------------|------------------------------------------------------------------------------------------------------|
| Incremental strategy     | `append` only (DuckDB lacks native `MERGE`). Use `delete+insert` via macro workaround.              |
| Snapshots                | Fully supported via `dbt-duckdb` adapter.                                                            |
| Concurrency              | Single-writer. Fine for learning. Set `threads: 1`.                                                  |
| Data types               | Mostly compatible. Use `TIMESTAMP` not `TIMESTAMPTZ`. DuckDB handles CSV seeds natively.             |
| Hooks                    | `GRANT` statements are meaningless — stub them with adapter-conditional Jinja.                       |
| Date spine generation    | Use `generate_series()` (DuckDB syntax) inside a conditional macro.                                 |

**profiles.yml (DuckDB):**
```yaml
novamart:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: "novamart.duckdb"
      threads: 1
      schema: main
```

**What you learn here:** Core dbt mechanics without infrastructure friction — macros, tests, incremental logic, snapshots. Focus entirely on SQL and Jinja.

---

### 4.2 PostgreSQL Variant

**Purpose:** Learn adapter behavior on a real client-server RDBMS with transactional semantics, indexing, permissions, and `GRANT` statements that matter.

**Adapter:** `dbt-postgres` 1.8+

**Setup:**
- Local PostgreSQL via Docker: `docker compose up -d` with a `docker-compose.yml` in the repo.
- Three schemas per environment: `raw_<source>`, `staging`, `intermediate`, `marts_core`, `marts_finance`, `marts_marketing`, `snapshots`.
- A `novamart_loader` role (read-write) and `novamart_reader` role (read-only on marts) to exercise hooks.

**Warehouse-specific considerations:**

| Concern                  | PostgreSQL Approach                                                                                  |
|--------------------------|------------------------------------------------------------------------------------------------------|
| Incremental strategy     | `delete+insert` (default for Postgres). Can also use `merge` on PG 15+ via `MERGE` statement.       |
| Snapshots                | Native support. `check` and `timestamp` strategies both work.                                        |
| Concurrency              | Multi-session safe. Use `threads: 4`.                                                                |
| Data types               | Use `TIMESTAMPTZ`, `NUMERIC(12,2)` for money, `TEXT` not `STRING`.                                   |
| Hooks                    | Real `GRANT SELECT ON {{ this }} TO novamart_reader;` in post-hooks.                                 |
| Date spine generation    | `generate_series(date, date, interval '1 day')`.                                                     |
| Indexes                  | Add `indexes` config on high-cardinality incremental models for query performance.                   |

**profiles.yml (PostgreSQL):**
```yaml
novamart:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5432
      user: novamart_loader
      password: "{{ env_var('NOVAMART_PG_PASSWORD') }}"
      dbname: novamart
      schema: dev
      threads: 4
    staging:
      type: postgres
      host: localhost
      port: 5432
      user: novamart_loader
      password: "{{ env_var('NOVAMART_PG_PASSWORD') }}"
      dbname: novamart
      schema: staging
      threads: 4
    prod:
      type: postgres
      host: localhost
      port: 5432
      user: novamart_loader
      password: "{{ env_var('NOVAMART_PG_PASSWORD') }}"
      dbname: novamart
      schema: prod
      threads: 4
```

**docker-compose.yml:**
```yaml
version: "3.9"
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: novamart
      POSTGRES_USER: novamart_loader
      POSTGRES_PASSWORD: localdev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./infra/init.sql:/docker-entrypoint-initdb.d/init.sql
volumes:
  pgdata:
```

**What you learn here:** Real DDL permissions, `GRANT` hooks, indexing, transactional behavior, `MERGE` on PG 15, and how dbt manages schemas on a real RDBMS.

---

### 4.3 Snowflake Variant

**Purpose:** Learn cloud-native warehouse features — clustering, warehouse sizing, RBAC, zero-copy clones, transient tables, and query tags.

**Adapter:** `dbt-snowflake` 1.8+

**Setup:**
- Snowflake trial account (30 days free, 400 credits).
- Database: `NOVAMART`, warehouse: `NOVAMART_WH` (X-Small).
- Roles: `NOVAMART_TRANSFORMER` (dbt runs), `NOVAMART_READER` (BI tool).
- Three environments via schemas: `DEV_<user>`, `STAGING`, `PROD`.

**Warehouse-specific considerations:**

| Concern                  | Snowflake Approach                                                                                   |
|--------------------------|------------------------------------------------------------------------------------------------------|
| Incremental strategy     | `merge` (native, default). Also explore `delete+insert` and `append`.                                |
| Snapshots                | Native support. Use `timestamp` strategy primarily.                                                  |
| Concurrency              | Massive. Use `threads: 8`.                                                                           |
| Data types               | `TIMESTAMP_NTZ`, `NUMBER(12,2)`, `VARCHAR`. Use `VARIANT` for semi-structured event payloads.        |
| Hooks                    | `GRANT SELECT ON {{ this }} TO ROLE NOVAMART_READER;`                                                |
| Transient tables         | Set `+transient: true` on staging/intermediate to save storage costs.                                |
| Query tags               | Use `+query_tag` config to tag all dbt queries for cost tracking.                                    |
| Clustering               | Add `cluster_by` on `fct_orders(order_date)` to learn cluster key management.                        |
| Date spine generation    | Use Snowflake `GENERATOR(ROWCOUNT => ...)` with `DATEADD`.                                           |
| Zero-copy clone          | Use `dbt clone` (1.7+) to clone prod into dev for testing against real data shapes.                  |

**profiles.yml (Snowflake):**
```yaml
novamart:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: NOVAMART_TRANSFORMER
      warehouse: NOVAMART_WH
      database: NOVAMART
      schema: "DEV_{{ env_var('USER', 'default') }}"
      threads: 8
      query_tag: "dbt_novamart_dev"
    prod:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: NOVAMART_TRANSFORMER
      warehouse: NOVAMART_WH
      database: NOVAMART
      schema: PROD
      threads: 8
      query_tag: "dbt_novamart_prod"
```

**What you learn here:** Cloud warehouse semantics — RBAC, transient tables, clustering, query tagging, zero-copy clones, and Snowflake-specific incremental merge behavior.

---

## 5. Orchestration Specifications

### 5.1 Apache Airflow Variant

**Purpose:** Learn how production teams schedule, monitor, and manage dbt runs outside of dbt Cloud.

**Setup:**
- Airflow via `astro dev init` (Astronomer CLI) or Docker Compose.
- Use `cosmos` (Astronomer's dbt-Airflow integration) to generate Airflow tasks from the dbt DAG automatically.

**DAG design:**

```
dag: novamart_daily
  schedule: 0 6 * * *  (daily at 06:00 UTC)

  task_group: seed_sources
    dbt_seed --select tag:daily

  task_group: staging
    [auto-generated from dbt DAG via cosmos]

  task_group: intermediate
    [auto-generated]

  task_group: marts
    [auto-generated]

  task_group: snapshots
    dbt_snapshot

  task_group: tests
    dbt_test --select tag:critical
    dbt_test --select tag:warning   (allowed to soft-fail)

  task: notify_on_failure
    slack_webhook on any upstream failure

  task: log_run_metadata
    dbt_run_operation log_run_metadata
```

**Key Airflow concepts exercised:**
- Task groups mirroring dbt layers.
- `cosmos` DbtDag / DbtTaskGroup to auto-parse `manifest.json`.
- Sensors for source freshness checks before run.
- Branching: skip marketing models on weekends.
- XCom: pass `dbt build` result counts to a Slack notification task.
- Retry policy: 2 retries with 5-minute delay on transient warehouse errors.

**Deliverable:** A working `dags/novamart_daily.py` and `dags/novamart_weekly_full_refresh.py`.

---

### 5.2 dbt Cloud Variant

**Purpose:** Learn dbt Cloud's managed orchestration, environment configuration, CI/CD via merge triggers, and the dbt Cloud API.

**Setup:**
- dbt Cloud developer account (free tier).
- GitHub repo connected to dbt Cloud project.
- Three environments: Development (IDE), Staging (CI), Production.

**Job design:**

| Job Name                     | Trigger            | Commands                                                  | Target   |
|------------------------------|--------------------|-----------------------------------------------------------|----------|
| `Daily Production Run`       | Cron 06:00 UTC     | `dbt build --select tag:daily`                            | `prod`   |
| `Weekly Full Refresh`        | Cron Sun 02:00 UTC | `dbt build --full-refresh --exclude tag:daily_only`       | `prod`   |
| `Snapshot Run`               | Cron 05:30 UTC     | `dbt snapshot`                                            | `prod`   |
| `CI — Slim Build`            | PR opened/updated  | `dbt build --select state:modified+ --defer --state prod` | `ci`     |
| `Source Freshness Check`     | Cron every 2h      | `dbt source freshness`                                    | `prod`   |

**Key dbt Cloud concepts exercised:**
- Environment-level configurations and overrides.
- `state:modified+` for slim CI — only test what changed.
- `--defer` to fall back to production models for unmodified refs.
- Webhooks for Slack/email notifications.
- dbt Cloud API: trigger a job from a Python script and poll for completion.
- Artifact storage: compare `manifest.json` across runs.

**Deliverable:** Fully configured dbt Cloud project with all five jobs, CI on PRs, and a Python script that triggers a run via the API.

---

## 6. Test-Driven Development Strategy

This section defines how TDD applies to dbt. The core loop is: **write a failing test → write the model → make the test pass → refactor.**

### 6.1 TDD Workflow in dbt

```
For each model:
  1. DEFINE the contract (schema.yml)
     - Column names, types, descriptions
     - Generic tests: unique, not_null, accepted_values, relationships
     - Custom generic tests: not_negative, valid_currency_code
     - dbt_expectations tests: distribution, recency, row count ranges

  2. WRITE a singular test (tests/singular/)
     - Business-rule assertion that should fail because the model doesn't exist yet
     - Example: "total order revenue equals sum of payment amounts"

  3. RUN `dbt test --select <model_name>` → observe the failure

  4. BUILD the model (write the SQL)

  5. RUN `dbt build --select <model_name>` → model + tests should pass

  6. REFACTOR the SQL for readability and performance

  7. RUN tests again → confirm still green
```

### 6.2 Test Categories

| Category           | Tool / Location                        | Purpose                                              | Failure Severity |
|--------------------|----------------------------------------|------------------------------------------------------|------------------|
| Schema tests       | `schema.yml` — `tests:` block         | Column-level contracts (unique, not_null, etc.)      | `ERROR`          |
| Custom generic     | `tests/generic/`                       | Reusable business rules (not_negative, valid FK)     | `ERROR`          |
| Singular tests     | `tests/singular/`                      | Cross-model business assertions                      | `ERROR`          |
| Data expectations  | `dbt_expectations` in `schema.yml`     | Statistical distribution, row count, recency         | `WARN`           |
| Source freshness   | `sources.yml` — `freshness:` block    | Detect stale source loads                            | `WARN` / `ERROR` |
| Unit tests         | `schema.yml` — `unit_tests:` block    | dbt 1.8 native unit tests with mocked inputs/outputs | `ERROR`          |

### 6.3 Unit Tests (dbt 1.8+)

dbt 1.8 introduced native unit tests. These let you test model logic with mocked input data — no real warehouse data needed.

Example for `fct_orders`:
```yaml
unit_tests:
  - name: test_fct_orders_calculates_total_correctly
    model: fct_orders
    given:
      - input: ref('stg_shopify__orders')
        rows:
          - { order_id: 1, customer_id: 10, order_date: "2024-01-15", status: "completed" }
      - input: ref('stg_shopify__order_items')
        rows:
          - { order_item_id: 1, order_id: 1, product_id: 100, quantity: 2, unit_price_cents: 1500 }
          - { order_item_id: 2, order_id: 1, product_id: 101, quantity: 1, unit_price_cents: 3000 }
      - input: ref('stg_stripe__payments')
        rows:
          - { payment_id: 1, order_id: 1, amount_cents: 6000, status: "succeeded" }
    expect:
      rows:
        - { order_id: 1, customer_id: 10, total_amount_dollars: 60.00, payment_status: "succeeded" }
```

**TDD flow with unit tests:**
1. Write the unit test YAML first (defines expected output).
2. Create a stub model that compiles but returns wrong results.
3. Run `dbt test --select test_type:unit` → see the failure.
4. Implement the real logic → test passes.

### 6.4 Test Coverage Targets

| Layer          | Required Tests per Model                                                                 |
|----------------|------------------------------------------------------------------------------------------|
| `staging`      | `unique` + `not_null` on primary key, `not_null` on critical fields, `accepted_values` where applicable |
| `intermediate` | At least 1 singular test per model asserting join correctness                            |
| `marts/dim_*`  | `unique`/`not_null` on surrogate key, `relationships` to source keys, 1 unit test        |
| `marts/fct_*`  | `unique`/`not_null` on grain key, `not_negative` on amounts, 1+ unit test, 1 singular test (reconciliation) |
| `marts/rpt_*`  | `not_null` on all dimensions, `dbt_expectations.expect_table_row_count_to_be_between`    |
| `snapshots`    | `unique` on surrogate key, `not_null` on `dbt_valid_from`, singular test for SCD2 correctness |

---

## 7. Macro Specifications

### 7.1 `generate_surrogate_key(field_list)`

Generates a deterministic surrogate key by MD5-hashing concatenated fields. Must handle nulls by coalescing to a sentinel string.

**Behavior:**
- Input: list of column name strings.
- Output: `VARCHAR` MD5 hash.
- Null handling: replace null with literal `'__NULL__'` before hashing.
- Must compile correctly on all three warehouse targets.

**Tests:** Unit test with known inputs → known hash output.

### 7.2 `union_sources(schema_pattern, table_name)`

Dynamically unions a table that exists across multiple schemas (e.g., regional shards: `raw_us.orders`, `raw_eu.orders`).

**Behavior:**
- Uses `dbt_utils.get_relations_by_pattern` or information schema query.
- Adds a `_source_schema` column to identify origin.
- Deduplicates if same PK appears in multiple schemas.

**Tests:** Singular test asserting row count equals sum of individual source counts.

### 7.3 `cents_to_dollars(column_name)`

Converts integer cents to `NUMERIC(12,2)` dollars: `({{ column_name }} / 100.0)::numeric(12,2)`.

**Tests:** Unit test with edge cases: 0, negative, large values.

### 7.4 `generate_date_spine(start_date, end_date)`

Produces a date dimension from start to end. Adapter-aware:
- DuckDB: `generate_series()`
- PostgreSQL: `generate_series()`
- Snowflake: `GENERATOR()` + `DATEADD()`

**Tests:** Assert row count equals date range span + 1. Assert no gaps.

### 7.5 `grant_select(role_name)`

Post-hook macro: `GRANT SELECT ON {{ this }} TO {{ role_name }}`. No-ops on DuckDB.

### 7.6 `log_run_metadata()`

`on-run-end` operation that inserts a row into `{{ target.schema }}.dbt_run_audit` with: `invocation_id`, `run_started_at`, `target_name`, `model_count`, `test_count`, `status`.

**Tests:** After a run, query the audit table and assert a row exists for the latest `invocation_id`.

---

## 8. Incremental Model Specifications

### 8.1 `fct_orders` (Incremental)

**Grain:** One row per `order_id`.

**Incremental strategy by warehouse:**

| Warehouse   | Strategy          | Unique Key     | Notes                                          |
|-------------|-------------------|----------------|-------------------------------------------------|
| DuckDB      | `delete+insert`   | `order_id`     | No native merge; macro handles delete then insert |
| PostgreSQL  | `merge` (PG 15+)  | `order_id`     | Uses `MERGE INTO` syntax                        |
| Snowflake   | `merge`           | `order_id`     | Native default                                  |

**Late-arriving data handling:**
- Lookback window of 72 hours: `where order_updated_at >= (select max(order_updated_at) - interval '72 hours' from {{ this }})`.
- `+on_schema_change: sync_all_columns` — if source adds a column, propagate it.

**Tests:**
- Unit test: mock 2 runs; assert second run only processes new/updated rows.
- Singular test: `fct_orders.total_amount` reconciles with `sum(stg_stripe__payments.amount)` for completed orders.
- Generic test: `not_negative` on `total_amount_dollars`.

### 8.2 `fct_payments` (Incremental)

**Grain:** One row per `payment_id`.

**Strategy:** `append` — payments are immutable once created.

**Idempotency guard:** Unique key constraint plus `where payment_id not in (select payment_id from {{ this }})` for DuckDB append safety.

### 8.3 `fct_sessions` (Incremental)

**Grain:** One row per `session_id`.

**Strategy:** `delete+insert` on all warehouses (sessions can get retroactively updated when late page_view events arrive).

**Lookback:** 24 hours.

---

## 9. Snapshot Specifications

### 9.1 `snap_customers`

| Property         | Value                                      |
|------------------|--------------------------------------------|
| Source           | `{{ source('app_db', 'users') }}`          |
| Strategy         | `timestamp`                                |
| Unique key       | `user_id`                                  |
| Updated at       | `updated_at`                               |
| Invalidate hard deletes | `true`                              |

**SCD2 output columns:** `user_id`, `email`, `name`, `tier`, `dbt_valid_from`, `dbt_valid_to`, `dbt_scd_id`, `dbt_updated_at`.

**Tests:**
- For any `user_id`, at most one record has `dbt_valid_to IS NULL` (the current record).
- `dbt_valid_from < dbt_valid_to` for all closed records.
- Singular test: load initial seeds → snapshot → load changed seeds → snapshot again → assert history rows exist.

### 9.2 `snap_products`

Same pattern as customers, on `{{ source('app_db', 'products') }}`, tracking `price` and `category` changes.

---

## 10. Source Freshness Specification

Defined in `models/staging/<source>/_sources.yml`:

| Source          | Loaded at field       | Warn after | Error after |
|-----------------|-----------------------|------------|-------------|
| `app_db`        | `_etl_loaded_at`      | 12 hours   | 24 hours    |
| `shopify`       | `_etl_loaded_at`      | 6 hours    | 12 hours    |
| `stripe`        | `_etl_loaded_at`      | 6 hours    | 12 hours    |
| `web_analytics`  | `_etl_loaded_at`     | 3 hours    | 6 hours     |

---

## 11. Exposure & Metrics Layer Specification

### 11.1 Exposures

```yaml
exposures:
  - name: executive_revenue_dashboard
    type: dashboard
    description: "Daily revenue, refund rate, and customer acquisition for leadership."
    depends_on:
      - ref('rpt_daily_revenue')
      - ref('dim_customers')
    owner:
      name: "Analytics Team"
      email: analytics@novamart.fake

  - name: marketing_channel_report
    type: analysis
    description: "Weekly channel performance and attribution."
    depends_on:
      - ref('rpt_channel_performance')
    owner:
      name: "Marketing Ops"
      email: mktg@novamart.fake
```

### 11.2 Semantic Layer / Metrics (dbt 1.8+ with MetricFlow)

```yaml
semantic_models:
  - name: orders
    defaults:
      agg_time_dimension: order_date
    model: ref('fct_orders')
    entities:
      - name: order_id
        type: primary
      - name: customer_id
        type: foreign
    dimensions:
      - name: order_date
        type: time
        type_params:
          time_granularity: day
      - name: order_status
        type: categorical
    measures:
      - name: total_revenue
        agg: sum
        expr: total_amount_dollars
      - name: order_count
        agg: count
        expr: order_id

metrics:
  - name: revenue
    type: simple
    type_params:
      measure: total_revenue

  - name: average_order_value
    type: derived
    type_params:
      expr: total_revenue / order_count
      metrics:
        - name: total_revenue
        - name: order_count
```

---

## 12. Configuration & Best Practices

### 12.1 `dbt_project.yml` (key sections)

```yaml
name: novamart
version: "1.0.0"
config-version: 2
profile: novamart

vars:
  novamart:
    payment_methods: ["credit_card", "paypal", "gift_card", "bank_transfer"]
    lookback_window_hours: 72

models:
  novamart:
    staging:
      +materialized: view
      +tags: ["staging", "daily"]
    intermediate:
      +materialized: ephemeral
      +tags: ["intermediate", "daily"]
    marts:
      core:
        +materialized: table
        +tags: ["core", "daily"]
      finance:
        +materialized: table
        +tags: ["finance", "daily"]
      marketing:
        +materialized: table
        +tags: ["marketing", "daily"]

snapshots:
  novamart:
    +tags: ["snapshot"]

seeds:
  novamart:
    +tags: ["seed"]

on-run-end:
  - "{{ log_run_metadata() }}"

dispatch:
  - macro_namespace: novamart
    search_order: ['novamart', 'dbt_utils', 'dbt']
```

### 12.2 Packages

```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
  - package: calogica/dbt_expectations
    version: [">=0.10.0", "<1.0.0"]
  - package: dbt-labs/codegen
    version: [">=0.12.0", "<1.0.0"]
```

### 12.3 Selectors (`selectors.yml`)

```yaml
selectors:
  - name: daily_build
    description: "Standard daily build — staging through marts"
    definition:
      union:
        - method: tag
          value: daily
        - method: tag
          value: snapshot

  - name: ci_slim
    description: "CI build — only modified models and their dependents"
    definition:
      method: state
      value: modified
      greedy: true  # include downstream dependents

  - name: finance_only
    description: "Finance team models"
    definition:
      method: tag
      value: finance
      children: true
```

---

## 13. Git & Branching Strategy

```
main                ← production-ready, triggers prod deploy
├── develop         ← integration branch
│   ├── feature/phase-1-staging
│   ├── feature/phase-2-incremental
│   ├── feature/phase-3-quality
│   └── ...
```

**Rules:**
- Every feature branch must pass `dbt build --select state:modified+` before merge.
- PRs require: all tests green, `dbt docs generate` succeeds, at least 1 new test per new model.
- Commit messages follow Conventional Commits: `feat(staging): add stg_shopify__orders model`.

---

## 14. Delivery Plan

### Phase 0: Foundation (Days 1–2)

**Goal:** Repo setup, tooling, and seed data.

| Task | Detail | Done When |
|------|--------|-----------|
| 0.1 | Initialize dbt project: `dbt init novamart` | `dbt debug` passes |
| 0.2 | Configure `profiles.yml` for first target (DuckDB recommended) | `dbt debug` passes with warehouse connection |
| 0.3 | Install packages (`dbt deps`) | `dbt_utils` macros available |
| 0.4 | Create `docker-compose.yml` for PostgreSQL | `docker compose up` starts PG, `psql` connects |
| 0.5 | Design and create all seed CSVs (initial + incremental sets) | `dbt seed` loads without error |
| 0.6 | Set up Git repo with `.gitignore`, branch strategy, pre-commit hooks | `sqlfluff lint` passes on empty project |
| 0.7 | Configure `sqlfluff` and `yamllint` for code style enforcement | Linter configs committed |
| 0.8 | Write project README with local setup instructions | A new contributor can run `dbt build` in <10 min |

**Pre-commit hooks:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/sqlfluff/sqlfluff
    hooks:
      - id: sqlfluff-lint
        args: ["--dialect", "ansi"]
      - id: sqlfluff-fix
  - repo: https://github.com/adrienverge/yamllint
    hooks:
      - id: yamllint
```

---

### Phase 1: Staging Layer + Macros (Days 3–7)

**Goal:** All four sources cleaned, typed, and tested. Core macros built.

**TDD sequence per source:**

```
For each source (app_db → shopify → stripe → web_analytics):
  1. Write _sources.yml with source definitions and freshness
  2. Write schema.yml for the staging model with ALL tests
  3. Run `dbt test` → fails (model doesn't exist)
  4. Write the staging model SQL
  5. Run `dbt build --select stg_<source>__<table>` → passes
```

| Task | Models | Tests Required |
|------|--------|----------------|
| 1.1 | `stg_app_db__users`, `stg_app_db__products`, `stg_app_db__addresses` | PK unique/not_null, email format, accepted_values on tier |
| 1.2 | `stg_shopify__orders`, `stg_shopify__order_items`, `stg_shopify__refunds` | PK, FK relationships, not_negative on quantities/amounts |
| 1.3 | `stg_stripe__payments`, `stg_stripe__charges`, `stg_stripe__refunds` | PK, accepted_values on status, currency code validation |
| 1.4 | `stg_web_analytics__sessions`, `stg_web_analytics__events` | PK, not_null on session_id, timestamp recency |
| 1.5 | Macro: `generate_surrogate_key` | Unit test with known hash |
| 1.6 | Macro: `cents_to_dollars` | Unit test with edge cases |
| 1.7 | Macro: `union_sources` | Test with two mock schemas |
| 1.8 | Macro: `generate_date_spine` | Row count = date range + 1 |

**Exit criteria:** `dbt build --select tag:staging` passes with 0 errors, 0 warnings.

---

### Phase 2: Intermediate + Core Marts + Snapshots (Days 8–14)

**Goal:** Cross-source joins, core dimensions and facts, incremental models, SCD2 snapshots.

| Task | Models | Key Concepts |
|------|--------|--------------|
| 2.1 | `int_orders_with_payments` | Multi-source join (Shopify orders + Stripe payments). TDD: write reconciliation singular test first. |
| 2.2 | `int_sessions_mapped_to_users` | Left join sessions to users on cookie/user_id. Handle anonymous sessions. |
| 2.3 | `int_product_inventory_current` | Latest inventory state per product. Window functions. |
| 2.4 | `dim_customers` | Surrogate key, full name, address denormalization. Unit test. |
| 2.5 | `dim_products` | Surrogate key, price in dollars, category enrichment. Unit test. |
| 2.6 | `dim_dates` | Generated via `generate_date_spine` macro. Test: no gaps, correct range. |
| 2.7 | `fct_orders` (incremental) | First incremental model. TDD: write unit test defining expected output of two successive runs. |
| 2.8 | `fct_payments` (incremental, append) | Simpler incremental. Test idempotency. |
| 2.9 | `snap_customers`, `snap_products` | Load initial seeds → snapshot → swap to incremental seeds → snapshot again → verify SCD2 history. |

**Key learning moments:**
- Task 2.7: You will hit the `is_incremental()` block for the first time. The unit test you write first will define the exact behavior you expect for new vs. updated rows.
- Task 2.9: Run `dbt snapshot` twice with different seed data. Query the snapshot table to see `dbt_valid_from`/`dbt_valid_to` populated correctly. Write a singular test that asserts "for each user, at most one record is current."

**Exit criteria:** `dbt build` for all models passes. Snapshot tables contain historical rows. Reconciliation tests pass.

---

### Phase 3: Finance & Marketing Marts + Data Quality (Days 15–20)

**Goal:** Domain-specific marts, advanced testing with `dbt_expectations`, audit logging.

| Task | Models | Key Concepts |
|------|--------|--------------|
| 3.1 | `fct_refunds` | Joins Shopify + Stripe refund data. Not incremental (low volume). |
| 3.2 | `rpt_daily_revenue` | Aggregated daily summary. Test: `dbt_expectations.expect_table_row_count_to_be_between`. |
| 3.3 | `fct_sessions` (incremental) | 24h lookback. Delete+insert strategy. Test sessionization logic with unit test. |
| 3.4 | `fct_attribution` | Last-touch attribution model. Complex window function logic. Unit test with known attribution path. |
| 3.5 | `rpt_channel_performance` | Aggregated by channel. Test: all channels present in output. |
| 3.6 | Implement `dbt_expectations` tests across all marts | Row count ranges, column value distributions, recency, no unexpected nulls. |
| 3.7 | Build `log_run_metadata` macro + audit table | Post-run hook writes metadata. Test: audit row exists after run. |
| 3.8 | Build `grant_select` hook macro | Adapter-conditional (no-op on DuckDB). Test on PostgreSQL: verify role has SELECT. |

**Exit criteria:** Full `dbt build` passes. `dbt_expectations` tests produce warnings (not errors) for distribution anomalies. Audit table populates.

---

### Phase 4: Semantic Layer & Documentation (Days 21–24)

**Goal:** Metrics definitions, exposures, full documentation.

| Task | Detail |
|------|--------|
| 4.1 | Define semantic models and metrics in YAML (per Section 11.2) |
| 4.2 | Define exposures (per Section 11.1) |
| 4.3 | Write `description:` for every model, column, source, and macro |
| 4.4 | Run `dbt docs generate` and `dbt docs serve` — review the DAG visually |
| 4.5 | Add model-level and column-level `meta:` tags for data governance (PII flagging, data owner) |

**Exit criteria:** `dbt docs serve` shows a fully documented project with no undocumented models. DAG renders correctly. Metrics compile.

---

### Phase 5: Multi-Warehouse + CI/CD (Days 25–30)

**Goal:** Run the project on all three warehouses. Set up CI pipelines.

| Task | Detail |
|------|--------|
| 5.1 | Configure PostgreSQL profile. Run full `dbt build`. Fix adapter-specific SQL. |
| 5.2 | Configure Snowflake profile. Run full `dbt build`. Add Snowflake-specific configs (transient, clustering, query_tag). |
| 5.3 | Review and fix all adapter-conditional macros (`generate_date_spine`, `grant_select`). |
| 5.4 | Set up `selectors.yml` (per Section 12.3). |
| 5.5 | Build GitHub Actions CI workflow: on PR → `dbt build --select state:modified+ --defer --state ./prod-artifacts/`. |
| 5.6 | Persist `manifest.json` from production runs as CI comparison artifact. |
| 5.7 | Add `sqlfluff` linting step to CI. |

**GitHub Actions workflow (`.github/workflows/dbt_ci.yml`):**
```yaml
name: dbt CI
on:
  pull_request:
    branches: [develop, main]

jobs:
  dbt-build:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: novamart
          POSTGRES_USER: novamart_loader
          POSTGRES_PASSWORD: ci_password
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install dbt-postgres dbt-utils sqlfluff
      - run: sqlfluff lint models/
      - run: dbt deps
      - name: Download production manifest
        uses: actions/download-artifact@v4
        with:
          name: prod-manifest
          path: ./prod-artifacts/
        continue-on-error: true  # First run won't have artifacts
      - run: dbt seed --target ci
      - run: dbt build --select state:modified+ --defer --state ./prod-artifacts/ --target ci
```

**Exit criteria:** CI pipeline triggers on PRs, runs slim build, and blocks merge on failure. All three warehouses produce identical analytical results.

---

### Phase 6: Orchestration (Days 31–36)

**Goal:** Implement both Airflow and dbt Cloud orchestration.

| Task | Detail |
|------|--------|
| 6.1 | Set up Airflow via Astronomer CLI (`astro dev init`). |
| 6.2 | Build `novamart_daily.py` DAG using `cosmos` (auto-parses dbt DAG). |
| 6.3 | Add source freshness sensor as first task in DAG. |
| 6.4 | Add Slack notification on failure. |
| 6.5 | Build `novamart_weekly_full_refresh.py` DAG. |
| 6.6 | Set up dbt Cloud project. Connect GitHub repo. |
| 6.7 | Configure all 5 dbt Cloud jobs (per Section 5.2). |
| 6.8 | Write Python script to trigger dbt Cloud job via API and poll for result. |
| 6.9 | Test CI job: open a PR, verify slim build runs in dbt Cloud. |

**Exit criteria:** Both Airflow and dbt Cloud can independently orchestrate the full pipeline. Slack notifications fire on failure. CI blocks broken PRs.

---

### Phase 7: Hardening & Retrospective (Days 37–40)

**Goal:** Polish, load test, document learnings.

| Task | Detail |
|------|--------|
| 7.1 | Generate a larger seed dataset (10K+ orders) and run full build. Identify slow models. |
| 7.2 | Optimize: add indexes (PG), clustering (Snowflake), materialization changes. |
| 7.3 | Run `dbt source freshness` end-to-end. Simulate a stale source and verify alerting. |
| 7.4 | Write a project retrospective document: what each feature taught you, gotchas per warehouse, what you'd do differently. |
| 7.5 | Tag the repo as `v1.0.0`. |

---

## 15. Definition of Done (per model)

A model is complete when ALL of the following are true:

- [ ] `schema.yml` entry exists with description, column docs, and all tests defined
- [ ] Generic tests: `unique` + `not_null` on primary key at minimum
- [ ] At least one business-logic test (singular or unit test)
- [ ] Model compiles and runs without error on the target warehouse
- [ ] All tests pass (`dbt test --select <model>`)
- [ ] SQL passes `sqlfluff lint` with no violations
- [ ] Model is tagged appropriately in `dbt_project.yml` or config block
- [ ] If incremental: idempotency verified (run twice, assert no duplicates)
- [ ] If snapshot: history verified (two snapshot runs with changed data, assert SCD2 rows)
- [ ] DAG placement is correct (`dbt docs generate` → visual check)

---

## 16. File Naming Conventions

| Entity      | Convention                         | Example                          |
|-------------|------------------------------------|----------------------------------|
| Source      | `_sources.yml`                     | `models/staging/shopify/_sources.yml` |
| Staging     | `stg_<source>__<entity>.sql`       | `stg_shopify__orders.sql`        |
| Intermediate| `int_<description>.sql`            | `int_orders_with_payments.sql`   |
| Dimension   | `dim_<entity>.sql`                 | `dim_customers.sql`              |
| Fact        | `fct_<entity>.sql`                 | `fct_orders.sql`                 |
| Report      | `rpt_<description>.sql`           | `rpt_daily_revenue.sql`          |
| Snapshot    | `snap_<entity>.sql`                | `snap_customers.sql`             |
| Schema YAML | `_<layer>__models.yml`             | `_core__models.yml`              |
| Macro       | `<verb>_<noun>.sql`                | `generate_surrogate_key.sql`     |
| Generic test| `test_<assertion>.sql`             | `test_not_negative.sql`          |
| Singular test| `assert_<rule>.sql`               | `assert_revenue_reconciles_with_payments.sql` |

---

## 17. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Snowflake trial credits expire before Phase 5 | Can't test Snowflake variant | Do Snowflake phase early or use Snowflake's free tier carefully; monitor credit usage. |
| DuckDB adapter missing features | Snapshot or incremental edge cases fail | Check `dbt-duckdb` changelog; fall back to `delete+insert` patterns. |
| `dbt_expectations` incompatibility with adapter | Tests fail to compile | Pin to known working version; use `dispatch` overrides if needed. |
| Seed data too simple | Tests pass trivially | Seed data intentionally includes: nulls, duplicates, negatives, late arrivals, orphan FKs. |
| Scope creep | Timeline slips | Each phase has strict exit criteria. Don't advance until criteria met. |
| Airflow `cosmos` version mismatch | DAG fails to parse dbt project | Pin `astronomer-cosmos` version; test with `astro dev pytest`. |

---

## Appendix A: Recommended Reading Order

Work through these as you reach each phase:

1. **Phase 0:** [dbt best practices](https://docs.getdbt.com/best-practices) — project structure guide
2. **Phase 1:** [Jinja & macros](https://docs.getdbt.com/docs/build/jinja-macros) — template reference
3. **Phase 2:** [Incremental models](https://docs.getdbt.com/docs/build/incremental-models) — all strategies explained
4. **Phase 2:** [Snapshots](https://docs.getdbt.com/docs/build/snapshots) — SCD2 deep dive
5. **Phase 3:** [dbt_expectations README](https://github.com/calogica/dbt-expectations) — test catalog
6. **Phase 4:** [MetricFlow / semantic layer](https://docs.getdbt.com/docs/build/metrics-overview)
7. **Phase 5:** [Slim CI](https://docs.getdbt.com/docs/deploy/continuous-integration) — `state:modified`
8. **Phase 6:** [Astronomer Cosmos docs](https://astronomer.github.io/astronomer-cosmos/)

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Grain** | The level of detail a fact table is defined at (e.g., one row per order) |
| **SCD Type 2** | Slowly Changing Dimension technique that preserves history by versioning rows |
| **Surrogate key** | A synthetic primary key (usually a hash) not derived from business data |
| **Slim CI** | CI strategy that only builds/tests models that changed (via `state:modified+`) |
| **Lookback window** | Time range an incremental model re-processes to catch late-arriving data |
| **Ephemeral** | dbt materialization that inlines the model as a CTE (no table/view created) |
| **Exposure** | dbt metadata declaring a downstream consumer (dashboard, report, ML model) |
| **Dispatch** | dbt mechanism to override a macro's implementation per adapter |

