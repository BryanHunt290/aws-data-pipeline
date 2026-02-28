# AWS Data Pipeline

This project provisions an S3 bucket using Terraform and includes a Python pipeline for data ingestion.

## Prerequisites

*   [Terraform](https://www.terraform.io/) (v1.0+)
*   [Python](https://www.python.org/) (v3.8+)
*   AWS Credentials configured locally

## Setup

1.  **Infrastructure**: Initialize and apply Terraform.
    ```bash
    terraform init
    terraform apply
    ```

2.  **Python Environment**:
    ```bash
    python -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    ```

## Usage

Run the pipeline ingestion script:

```bash
python -m src.pipeline.run --ingest-sample
```