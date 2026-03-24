/* @bruin
name: mart.keepa_opportunities
type: athena.sql
description: Mart for Keepa-based wholesale opportunities - buy box, rank, offers

depends:
  - curated.keepa_watchlist

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
  - name: snapshot_date
    type: date
@bruin */

SELECT
  asin,
  buy_box_price,
  sales_rank,
  offer_count,
  CURRENT_DATE AS snapshot_date
FROM curated_keepa_watchlist
WHERE asin IS NOT NULL
