-- Redshift DDL: Schemas and partitioned table
-- Run as admin after connecting to Redshift

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;

-- Partitioned table (year, month) for processed sales
CREATE TABLE IF NOT EXISTS raw.sales_processed (
    category          VARCHAR(64),
    total_quantity    BIGINT,
    total_revenue     DOUBLE PRECISION,
    transaction_count BIGINT,
    year              SMALLINT,
    month             SMALLINT
)
DISTSTYLE AUTO
SORTKEY (year, month);
