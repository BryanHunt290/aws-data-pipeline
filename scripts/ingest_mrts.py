#!/usr/bin/env python3
"""
Backfill ingestion for US Census MRTS (Monthly Retail Trade Sales).
Downloads MRTS data from Census.gov and uploads to S3 raw prefix.

Usage:
  pip install boto3 requests  # if not already installed
  python scripts/ingest_mrts.py [--ingest-date YYYY-MM-DD] [--bucket BUCKET]
  # Uses AWS_REGION, DATA_BUCKET from env or .env

Output: s3://<bucket>/raw/retail_sales/ingest_date=YYYY-MM-DD/<filename>.csv
"""

import argparse
import os
import sys
from datetime import date

import boto3
import requests

# MRTS file URLs (Census.gov - free, no API key)
MRTS_FILES = {
    "retail_and_food_services": "https://www.census.gov/retail/marts/www/adv44X72.txt",
    "retail_total": "https://www.census.gov/retail/marts/www/adv44000.txt",
    "food_and_beverage": "https://www.census.gov/retail/marts/www/adv44500.txt",
    "motor_vehicle": "https://www.census.gov/retail/marts/www/adv44100.txt",
}


def get_bucket() -> str:
    bucket = os.getenv("DATA_BUCKET") or os.getenv("MRTS_DATA_BUCKET")
    if not bucket:
        raise ValueError(
            "Set DATA_BUCKET or MRTS_DATA_BUCKET (e.g. from terraform output data_bucket)"
        )
    return bucket


def ingest_mrts(
    bucket: str,
    ingest_date_str: str,
    region: str = "us-east-1",
    dry_run: bool = False,
) -> dict:
    """Download MRTS files and upload to S3."""
    s3 = boto3.client("s3", region_name=region)
    prefix = f"raw/retail_sales/ingest_date={ingest_date_str}/"
    results = []

    for category, url in MRTS_FILES.items():
        try:
            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            content = resp.text
        except Exception as e:
            results.append({"category": category, "status": "failed", "error": str(e)})
            continue

        key = f"{prefix}{category}.csv"
        if dry_run:
            results.append({"category": category, "status": "dry_run", "key": key})
            continue

        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=content.encode("utf-8"),
            ContentType="text/plain",
        )
        results.append({"category": category, "status": "ok", "key": key})

    return {"ingest_date": ingest_date_str, "results": results}


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest MRTS data to S3")
    parser.add_argument(
        "--ingest-date",
        default=date.today().isoformat(),
        help="Ingest date (YYYY-MM-DD)",
    )
    parser.add_argument("--bucket", help="S3 bucket (overrides DATA_BUCKET)")
    parser.add_argument("--region", default=os.getenv("AWS_REGION", "us-east-1"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    bucket = args.bucket or get_bucket()
    result = ingest_mrts(
        bucket=bucket,
        ingest_date_str=args.ingest_date,
        region=args.region,
        dry_run=args.dry_run,
    )
    print(result)
    failed = [r for r in result["results"] if r["status"] == "failed"]
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
