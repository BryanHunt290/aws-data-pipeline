# AWS Data Pipeline — Sales Analytics

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-623CE4?logo=terraform)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20Glue%20%7C%20Step%20Functions-FF9900?logo=amazon-aws)](https://aws.amazon.com)
[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python)](https://python.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

End-to-end AWS data pipeline: ingest raw CSV → Glue ETL (PySpark) → S3 Parquet → Athena → Streamlit dashboard **or Power BI Desktop** (via ODBC).

---

## Quick Start (First-Time Setup)

```bash
# Clone (or cd into existing repo)
git clone <your-repo-url> && cd aws-data-pipeline

# 1. Deploy infrastructure
make deploy

# 2. Configure .env for dashboard
make setup-env

# 3. Upload sample data
make upload

# 4. Run pipeline (wait ~2–3 min)
make run

# 5. Run Glue Crawler (wait ~1–2 min)
make crawler

# 6. Launch dashboard
make dashboard
```

Open **http://localhost:8501** for the Sales Analytics Dashboard.

---

## Future Runs

After initial setup, use this order every time:

| Step | Command | Wait |
|------|----------|------|
| 1 | `make upload` | — |
| 2 | `make run` | ~2–3 min |
| 3 | `make crawler` | ~1–2 min |
| 4 | `make dashboard` | — |

**Verify pipeline state anytime:**
```bash
make verify
```

---

## Makefile Reference

| Command | Description |
|---------|-------------|
| `make deploy` | Deploy Terraform (S3, Glue, Lambda, Step Functions, Athena) |
| `make setup-env` | Generate `.env` from Terraform outputs |
| `make upload` | Upload `data/sample_data.csv` to S3 raw/ |
| `make run` | Start Step Functions pipeline (Glue ETL) |
| `make crawler` | Run Glue Crawler to catalog processed data for Athena |
| `make verify` | Check raw data, processed data, and Glue job status |
| `make dashboard` | Launch Streamlit dashboard |
| `make destroy` | Tear down all AWS resources |

---

## Bruin (Athena transforms)

`make setup-env` generates `.bruin.yml` with an Athena connection. Use [Bruin CLI](https://getbruin.com) to run SQL transforms in Athena:

- **Connection:** `athena-default` (Glue DB: `data_pipeline_demo_catalog`)
- **Credentials:** AWS profile `default` or `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- **Query results:** S3 path from Terraform output `athena_results_bucket`

**Keepa flow:** Ingest writes JSONL to `keepa/raw/`, Athena table `keepa_raw` reads it, curated/mart SQL assets transform. See [README_BRUIN.md](README_BRUIN.md).

---

## Power BI Desktop (Amazon Athena)

Connect Power BI to the same Glue/Athena data as the pipeline (no Streamlit required).

### 1. Values from this project

Run from the repo root (after `make setup-env`):

| Setting | How to get it |
|--------|----------------|
| **Region** | `grep AWS_REGION .env` or `cd infrastructure/terraform && terraform output -raw aws_region` |
| **Workgroup** | `terraform output -raw athena_workgroup` (default: `data-pipeline-demo`) |
| **Query results S3** | `terraform output -raw athena_results_bucket` → use `s3://<bucket>/results/` |
| **Glue database** | `terraform output -raw glue_database` (default: `data_pipeline_demo_catalog`) |
| **Table** | `processed` (after `make crawler` so Parquet under `processed/` is cataloged) |

### 2. Install the ODBC driver

- Install **Amazon Athena ODBC driver** (Simba). See [AWS documentation — ODBC driver](https://docs.aws.amazon.com/athena/latest/ug/connect-with-odbc.html).

### 3. Create an ODBC DSN (Windows: ODBC Data Source Administrator 64-bit)

1. **Add** → choose the Simba / Athena driver.
2. **Aws Region** → your region (e.g. `us-west-2`).
3. **S3 Output Location** → `s3://<athena_results_bucket>/results/` (must be writable by your IAM user/role).
4. **Workgroup** → e.g. `data-pipeline-demo`.
5. **Authentication** → IAM credentials or AWS profile (match how you use `aws` CLI / SSO).
6. Save / test.

### 4. Power BI Desktop

1. **Get data** → **ODBC** → select your DSN.
2. **Navigator** → database `data_pipeline_demo_catalog` → table **`processed`**.
3. **Load** or **Transform Data**.

### 5. Scheduled refresh (optional)

Power BI **Service** scheduled refresh usually needs an **on-premises data gateway** on a machine that has the same ODBC driver and AWS access.

### Troubleshooting

- **Access denied on S3:** IAM user/role needs `s3:PutObject` on the Athena results bucket prefix and Glue/Athena permissions.
- **Empty or old data:** Run `make crawler` after `make run` so the `processed` table matches the latest Parquet.

---

## Prerequisites

- **Terraform** 1.0+
- **AWS CLI** configured (`aws configure` or env vars)
- **Python** 3.10+

---

## Architecture

```
Raw CSV → S3 raw/ → Step Functions → Glue (PySpark) → S3 processed/ → Athena → Dashboard
```

| Component | Purpose |
|-----------|---------|
| **S3 raw/** | Raw CSV input |
| **S3 processed/** | Parquet output (aggregated by category, year, month) |
| **Glue** | PySpark ETL: read raw, transform, write Parquet |
| **Step Functions** | Orchestrate Glue job (sync wait) |
| **Athena** | Query S3 via Glue Catalog |
| **Streamlit** | Two-tile dashboard (line + bar charts) |

---

## Dashboard Tiles

| Tile | Type | Chart |
|------|------|-------|
| **Tile 1** | Time-based | Revenue over time (line chart) |
| **Tile 2** | Categorical | Revenue by category (bar chart) |

---

## Troubleshooting

### "No data" on dashboard

1. Run `make verify` to check raw and processed data.
2. Ensure you ran **in order**: `upload` → `run` → `crawler`.
3. Wait 2–3 min after `make run` before `make crawler`.

### Glue job fails (403 / S3 access)

The Glue role needs read access to the scripts bucket. Ensure Terraform is applied:

```bash
cd infrastructure/terraform && terraform apply -auto-approve
```

### Athena "table not found"

Run the crawler and wait 1–2 min:

```bash
make crawler
```

### Dashboard can't connect

1. Ensure `.env` exists: `make setup-env`
2. Set `ATHENA_RESULTS_BUCKET` (from `terraform output athena_results_bucket`)

### Streamlit: "Failed to fetch dynamically imported module" (static JS)

Usually a **browser cache** or **stale Streamlit** issue. Try: stop the app, run `streamlit cache clear`, start again, then **hard refresh** the browser (Cmd+Shift+R / Ctrl+Shift+R). If it persists, `pip install -U streamlit` in the same venv as `make dashboard`.

---

## Project Structure

```
├── data/
│   └── sample_data.csv          # Sample input (10 rows)
├── glue/
│   └── transform_job.py        # PySpark ETL
├── lambda/
│   └── trigger_glue.py         # Lambda trigger (optional)
├── dashboard/
│   ├── app.py                  # Streamlit dashboard
│   └── requirements.txt
├── infrastructure/
│   └── terraform/              # S3, Glue, Lambda, Step Functions, Athena
├── scripts/
│   ├── upload_sample_data.sh
│   ├── run_pipeline.sh
│   ├── run_crawler.sh
│   └── verify_pipeline.sh
├── Makefile
├── .env.example
└── README.md
```

---

## Optional: Redshift Path

For full data warehouse evaluation (Redshift + dbt):

1. Enable Redshift in Terraform: `terraform apply -var="enable_redshift=true"`
2. Run DDL: `psql -h <host> -U admin -d sales -f sql/redshift/01_ddl.sql`
3. Run COPY: `python scripts/copy_to_redshift.py`
4. Run dbt: `cd dbt && dbt build`
5. Set `USE_REDSHIFT=true` in `.env`

---

## License

MIT
