/* @bruin
name: mart.wholesale_opportunities
type: athena.sql
description: Mart table for wholesale decisions - joins buy box, rank trend, offer count, supplier cost

depends:
  - raw.supplier_cost
  - raw.buy_box_latest
  - raw.rank_trend
  - raw.offer_count_trend
  - raw.watchlist

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
  - name: avg_rank_30d
    type: double
  - name: rank_trend_30d
    type: double
  - name: avg_rank_90d
    type: double
  - name: rank_trend_90d
    type: double
  - name: offer_count_trend_30d
    type: double
  - name: supplier_cost
    type: double
    checks:
      - name: non_negative
  - name: estimated_profit
    type: double
  - name: roi
    type: double
  - name: flags
    type: string
  - name: snapshot_date
    type: date

custom_checks:
  - name: rows_exist
    description: Table must have at least one row
    query: SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM mart_wholesale_opportunities
    value: 1
  - name: rows_exist_for_todays_partition
    description: At least one row for current snapshot date
    query: SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM mart_wholesale_opportunities WHERE snapshot_date = CURRENT_DATE
    value: 1
  - name: watchlist_coverage_pct
    description: Watchlist coverage must be >= 80%
    query: |
      SELECT CASE
        WHEN (SELECT COUNT(*) FROM raw_watchlist) = 0 THEN 1
        WHEN (SELECT COUNT(DISTINCT m.asin) FROM mart_wholesale_opportunities m
              INNER JOIN raw_watchlist w ON m.asin = w.asin) * 100.0
             / (SELECT COUNT(*) FROM raw_watchlist) >= 80 THEN 1
        ELSE 0
      END
    value: 1
    blocking: false
@bruin */

WITH buy_box AS (
  SELECT asin, buy_box_price
  FROM raw_buy_box_latest
),
rank_data AS (
  SELECT asin, avg_rank_30d, rank_trend_30d, avg_rank_90d, rank_trend_90d
  FROM raw_rank_trend
),
offer_data AS (
  SELECT asin, offer_count_trend_30d
  FROM raw_offer_count_trend
),
supplier AS (
  SELECT asin, supplier_cost
  FROM raw_supplier_cost
),
joined AS (
  SELECT
    COALESCE(b.asin, r.asin, o.asin, s.asin) AS asin,
    b.buy_box_price,
    r.avg_rank_30d,
    r.rank_trend_30d,
    r.avg_rank_90d,
    r.rank_trend_90d,
    o.offer_count_trend_30d,
    s.supplier_cost,
    -- Estimated profit: buy_box - supplier_cost (simplified; adjust for fees as needed)
    b.buy_box_price - s.supplier_cost AS estimated_profit,
    -- ROI: (profit / cost) * 100
    CASE
      WHEN s.supplier_cost > 0
      THEN 100.0 * (b.buy_box_price - s.supplier_cost) / s.supplier_cost
      ELSE NULL
    END AS roi
  FROM buy_box b
  FULL OUTER JOIN rank_data r ON b.asin = r.asin
  FULL OUTER JOIN offer_data o ON COALESCE(b.asin, r.asin) = o.asin
  FULL OUTER JOIN supplier s ON COALESCE(b.asin, r.asin, o.asin) = s.asin
),
with_flags AS (
  SELECT
    asin,
    buy_box_price,
    avg_rank_30d,
    rank_trend_30d,
    avg_rank_90d,
    rank_trend_90d,
    offer_count_trend_30d,
    supplier_cost,
    estimated_profit,
    roi,
    -- Build flags for wholesale decisions
    CONCAT_WS(
      ', ',
      CASE WHEN offer_count_trend_30d >= 0.3 THEN 'offers_spiking' END,
      CASE WHEN rank_trend_30d BETWEEN -0.02 AND 0.02 AND rank_trend_30d IS NOT NULL THEN 'rank_flat' END,
      CASE WHEN offer_count_trend_30d >= 0.4 AND rank_trend_30d < -0.1 THEN 'buybox_unstable' END,
      CASE WHEN roi >= 50 THEN 'high_roi' END,
      CASE WHEN estimated_profit >= 10 THEN 'high_margin' END
    ) AS flags
  FROM joined
)
SELECT
  asin,
  buy_box_price,
  avg_rank_30d,
  rank_trend_30d,
  avg_rank_90d,
  rank_trend_90d,
  offer_count_trend_30d,
  supplier_cost,
  ROUND(estimated_profit, 2) AS estimated_profit,
  ROUND(roi, 2) AS roi,
  NULLIF(TRIM(flags), '') AS flags,
  CURRENT_DATE AS snapshot_date
FROM with_flags
WHERE asin IS NOT NULL
ORDER BY roi DESC NULLS LAST, estimated_profit DESC NULLS LAST
