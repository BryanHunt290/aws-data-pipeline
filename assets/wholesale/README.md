# Wholesale Opportunities Mart

Mart table for wholesale decisions. Joins buy box price, rank trends, offer count trends, and supplier cost.

## Output: `mart.wholesale_opportunities`

| Column | Type | Description |
|--------|------|-------------|
| asin | string | Amazon ASIN |
| buy_box_price | double | Latest buy box / new price |
| avg_rank_30d | double | 30-day average rank |
| rank_trend_30d | double | 30-day rank trend |
| avg_rank_90d | double | 90-day average rank |
| rank_trend_90d | double | 90-day rank trend |
| offer_count_trend_30d | double | 30-day offer count trend |
| supplier_cost | double | Cost from supplier |
| estimated_profit | double | buy_box_price - supplier_cost |
| roi | double | Return on investment % |
| flags | string | e.g. "offers_spiking", "rank_flat", "buybox_unstable", "high_roi", "high_margin" |
| snapshot_date | date | Partition date (CURRENT_DATE) |

## Upstream Seeds (CSV)

- `seeds/supplier_cost.csv` - Supplier cost by ASIN
- `seeds/buy_box_latest.csv` - Latest buy box price
- `seeds/rank_trend.csv` - 30/90-day rank and trend
- `seeds/offer_count_trend.csv` - Offer count and trend

## Data Quality Checks

| Check | Type | Description |
|-------|------|-------------|
| **no null ASINs** | column | `not_null` on asin |
| **price >= 0** | column | `non_negative` on buy_box_price, supplier_cost |
| **rows exist** | custom | Table has at least one row |
| **rows for today's partition** | custom | snapshot_date = CURRENT_DATE has rows |
| **watchlist coverage %** | custom | >= 80% of watchlist ASINs in mart (non-blocking) |

Run checks only:
```bash
bruin run --only checks mart.wholesale_opportunities
```

## Run

```bash
# 1. Run seeds (loads CSVs to Athena)
bruin run raw.supplier_cost raw.buy_box_latest raw.rank_trend raw.offer_count_trend raw.watchlist

# 2. Run mart (includes quality checks)
bruin run mart.wholesale_opportunities
```

Or run all:
```bash
bruin run mart.wholesale_opportunities --include-deps
```

## Replace with Real Data

For production, replace seeds with real sources:
- Buy box: SP-API or Keepa
- Rank: Brand Analytics or third-party
- Offer count: SP-API
- Supplier cost: ERP/CSV in S3
