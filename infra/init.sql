-- Initialize NovaMart PostgreSQL database
-- Creates roles and schemas for the dbt project

-- Read-only role for BI tools / downstream consumers
CREATE ROLE novamart_reader WITH LOGIN PASSWORD 'reader_localdev';

-- Grant connect
GRANT CONNECT ON DATABASE novamart TO novamart_reader;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS raw_app_db;
CREATE SCHEMA IF NOT EXISTS raw_shopify;
CREATE SCHEMA IF NOT EXISTS raw_stripe;
CREATE SCHEMA IF NOT EXISTS raw_web_analytics;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS intermediate;
CREATE SCHEMA IF NOT EXISTS marts_core;
CREATE SCHEMA IF NOT EXISTS marts_finance;
CREATE SCHEMA IF NOT EXISTS marts_marketing;
CREATE SCHEMA IF NOT EXISTS snapshots;

-- Grant usage on mart schemas to reader role
GRANT USAGE ON SCHEMA marts_core TO novamart_reader;
GRANT USAGE ON SCHEMA marts_finance TO novamart_reader;
GRANT USAGE ON SCHEMA marts_marketing TO novamart_reader;

-- Default privileges: auto-grant SELECT on future tables in mart schemas
ALTER DEFAULT PRIVILEGES IN SCHEMA marts_core GRANT SELECT ON TABLES TO novamart_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA marts_finance GRANT SELECT ON TABLES TO novamart_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA marts_marketing GRANT SELECT ON TABLES TO novamart_reader;
