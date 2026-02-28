# DE Zoomcamp Final Project: US Census MRTS Retail Sales Pipeline

## Problem Statement

**Business question:** How do US retail and food services sales trends evolve over time, and which categories show the strongest year-over-year growth?

This pipeline ingests the free [US Census Monthly Retail Trade Sales (MRTS)](https://www.census.gov/retail/marts/www/timeseries.html) data, transforms it to a queryable Parquet format, and exposes analytics via Athena and a Streamlit dashboard.

---

## Architecture

```
                    +------------------+
                    |  Census.gov      |
                    |  (MRTS .txt)     |
                    +--------+---------+
                             |
                             v
+------------------+  ingest_mrts.py   +------------------+
|  EventBridge     |<-----------------|  S3 Raw           |
|  (daily 06:00)   |                   |  raw/retail_sales/|
+--------+---------+                   |  ingest_date=...  |
         |                             +--------+----------+
         v                                      |
+------------------+                            v
|  Step Functions  |                 +------------------+
|  (orchestration) |---------------->|  Glue ETL Job    |
+------------------+                 |  (Spark/Python)   |
                                     +--------+---------+
                                              |
                                              v
                                     +------------------+
                                     |  S3 Curated       |
                                     |  curated/         |
                                     |  year=.../month= |
                                     +--------+--------+
                                              |
                                              v
                                     +------------------+
                                     |  Athena          |
                                     |  (Glue Catalog)  |
                                     +--------+---------+
                                              |
                                              v
                                     +------------------+
                                     |  Streamlit       |
                                     |  Dashboard       |
                                     +------------------+
```

---

## File Structure

```
aws-data-pipeline/
├── infra/                    # Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── kms.tf
│   ├── s3.tf
│   ├── iam.tf
│   ├── glue.tf
│   ├── stepfunctions.tf
│   ├── athena.tf
│   └── outputs.tf
├── etl/
│   └── mrts_etl.py           # Glue job script
├── scripts/
│   └── ingest_mrts.py        # Backfill ingestion
├── sql/
│   ├── 01_retail_sales_monthly.sql
│   ├── 02_retail_sales_yoy_growth.sql
│   └── 03_retail_sales_seasonality.sql
├── dashboard/
│   ├── app.py
│   └── requirements.txt
├── .env.example
└── README.md
```

---

## How to Deploy

### 1. Terraform

```bash
cd infra
terraform init
terraform plan
terraform apply
```

### 2. Backfill Ingestion (one-time or monthly)

```bash
# Set env from terraform output
export DATA_BUCKET=$(cd infra && terraform output -raw data_bucket)

# Ingest
python scripts/ingest_mrts.py --ingest-date 2025-02-27
```

### 3. Run Pipeline (Glue ETL)

**Option A: Via Step Functions (full: Crawler → Glue → Crawler)**

```bash
aws stepfunctions start-execution \
  --state-machine-arn $(cd infra && terraform output -raw state_machine_arn)
```

**Option B: Glue job only**

```bash
aws glue start-job-run --job-name $(cd infra && terraform output -raw glue_job_name)
```

**Option C: EventBridge (scheduled daily 06:00 UTC)**

The pipeline runs automatically. No action needed.

---

## How to Query in Athena

1. Open Athena in AWS Console.
2. Set workgroup: `mrts-retail-sales-dev` (from `terraform output athena_workgroup`).
3. Set database: `mrts_retail_sales_dev_catalog` (from `terraform output glue_database`).
4. Run SQL from `sql/`:

```sql
-- Base table (after Glue ETL + Crawler)
SELECT * FROM retail_sales LIMIT 10;

-- Analytics views (run 01, 02, 03 first)
SELECT * FROM retail_sales_monthly WHERE year = 2024;
SELECT * FROM retail_sales_yoy_growth WHERE year = 2024;
SELECT * FROM retail_sales_seasonality WHERE year = 2024;
```

---

## How to Run Dashboard

```bash
cp .env.example .env
# Edit .env with terraform outputs:
#   DATA_BUCKET, ATHENA_WORKGROUP, GLUE_DATABASE, ATHENA_RESULTS_BUCKET

cd dashboard
pip install -r requirements.txt
streamlit run app.py
```

---

## Cost Notes

| Component      | Approximate cost                          |
|----------------|-------------------------------------------|
| S3             | ~$0.023/GB/month (raw + curated)          |
| Glue           | ~$0.44/DPU-hour (2 workers × ~5 min/run)   |
| Athena         | $5/TB scanned (use partition filters)     |
| Step Functions | Free tier: 4,000 transitions/month         |
| EventBridge    | Free for scheduled rules                   |

**Partitioning:** Curated data is partitioned by `year` and `month`. Always filter on these columns in Athena to reduce scan cost.

---

## Partitioning Notes

- **Raw:** `s3://bucket/raw/retail_sales/ingest_date=YYYY-MM-DD/` — one partition per ingestion run.
- **Curated:** `s3://bucket/curated/retail_sales/year=YYYY/month=MM/` — partition pruning in Athena via `WHERE year = ... AND month = ...`.

---

## Constraints Met

- No hardcoded account IDs (uses `data.aws_caller_identity`)
- Parameterized via Terraform variables and Glue job arguments
- `.env.example` for local dashboard
- Clean, professional file structure
