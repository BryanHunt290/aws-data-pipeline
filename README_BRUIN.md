# Bruin Pipeline - Wholesale Opportunities & Keepa

## Prerequisites

```bash
make setup-env   # Generates .env and .bruin.yml from Terraform outputs
source .env     # Or: export $(grep -v '^#' .env | xargs)
```

The ingest asset requires `S3_BUCKET` (set by `make setup-env`).

**AWS region:** Set in Terraform (`infrastructure/terraform/variables.tf` or `terraform apply -var="aws_region=us-west-2"`). After changing region, run `terraform apply` and `make setup-env` so `.env` and `.bruin.yml` get the correct `AWS_REGION` and Athena connection region.

## Run Order

### 1. Keepa ingestion (writes JSONL to S3)

```bash
bruin run assets/ingest_keepa_watchlist.py
```

Fetches watchlist data from Keepa API (or mock when no API key). Writes JSONL to `s3://bucket/keepa/raw/ingest_date=YYYY-MM-DD/`.

**ASINs:** Edit `seeds/watchlist_asins.csv` (20–50 ASINs). Default: 40 ASINs.

**Secrets:** Add `keepa_api_key` to Bruin for real Keepa data.

### 2. Keepa curated + mart (Athena SQL)

```bash
bruin run mart.keepa_opportunities --include-deps
```

Runs `curated.keepa_watchlist` (reads from Glue table `keepa_raw`) then `mart.keepa_opportunities`.

### 3. Wholesale mart (seeds + mart)

```bash
bruin run mart.wholesale_opportunities --include-deps
```

Runs seeds (supplier_cost, buy_box_latest, etc.) and mart.

## Pipeline Structure

| Step | Asset | Description |
|------|-------|-------------|
| 1 | `assets/ingest_keepa_watchlist.py` | Keepa API → S3 `keepa/raw/` JSONL |
| 2 | `keepa_raw` (Glue) | Athena external table over `keepa/raw/` |
| 3 | `curated.keepa_watchlist` | SQL: keepa_raw → curated table |
| 4 | `mart.keepa_opportunities` | SQL: curated → mart table |
| 5 | `raw.supplier_cost` | Seed: supplier cost CSV |
| 6 | `raw.buy_box_latest` | Seed: buy box CSV |
| 7 | `raw.rank_trend` | Seed: rank trend CSV |
| 8 | `raw.offer_count_trend` | Seed: offer count CSV |
| 9 | `raw.watchlist` | Seed: watchlist CSV |
| 10 | `mart.wholesale_opportunities` | Mart: joins all → mart table |

## Dependencies

For the Python ingest asset:
```bash
pip install pandas keepa boto3  # or use assets/requirements.txt
```
