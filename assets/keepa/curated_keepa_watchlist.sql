/* @bruin
name: curated.keepa_watchlist
type: athena.sql
description: Curated Keepa watchlist - parses raw JSONL, latest snapshot per ASIN

depends:
  - raw.keepa_watchlist

materialization:
  type: table

columns:
  - name: asin
    type: string
    checks:
      - name: not_null
  - name: buy_box_price
    type: double
    checks:
      - name: non_negative
  - name: sales_rank
    type: integer
  - name: offer_count
    type: integer
  - name: captured_at
    type: string
@bruin */

-- Read from Glue table keepa_raw (external table over S3 JSONL)
-- Use last 7 days of partitions for freshness
WITH latest AS (
  SELECT *
  FROM keepa_raw
  WHERE ingest_date >= CURRENT_DATE - INTERVAL '7' DAY
),
deduped AS (
  SELECT
    asin,
    buy_box_price,
    sales_rank,
    offer_count,
    captured_at,
    ROW_NUMBER() OVER (PARTITION BY asin ORDER BY captured_at DESC) AS rn
  FROM latest
)
SELECT
  asin,
  buy_box_price,
  CAST(sales_rank AS INTEGER) AS sales_rank,
  CAST(offer_count AS INTEGER) AS offer_count,
  captured_at
FROM deduped
WHERE rn = 1
  AND asin IS NOT NULL
  AND asin != ''
