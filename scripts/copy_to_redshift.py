#!/usr/bin/env python3
"""
Load Parquet from S3 into Redshift raw.sales_processed.
Run after: terraform apply with enable_redshift=true, DDL executed.

Env: REDSHIFT_HOST, REDSHIFT_USER, REDSHIFT_PASSWORD, S3_BUCKET, REDSHIFT_IAM_ROLE_ARN
"""

import os
import sys

import psycopg2
from dotenv import load_dotenv

load_dotenv()

for k in ["REDSHIFT_HOST", "REDSHIFT_USER", "REDSHIFT_PASSWORD", "S3_BUCKET", "REDSHIFT_IAM_ROLE_ARN"]:
    if not os.getenv(k):
        print(f"Set {k} in .env", file=sys.stderr)
        sys.exit(1)

conn = psycopg2.connect(
    host=os.getenv("REDSHIFT_HOST"),
    port=os.getenv("REDSHIFT_PORT", "5439"),
    dbname=os.getenv("REDSHIFT_DATABASE", "sales"),
    user=os.getenv("REDSHIFT_USER"),
    password=os.getenv("REDSHIFT_PASSWORD"),
)
conn.autocommit = True
cur = conn.cursor()

bucket = os.getenv("S3_BUCKET")
role = os.getenv("REDSHIFT_IAM_ROLE_ARN")

cur.execute("TRUNCATE TABLE raw.sales_processed")
cur.execute(f"""
    COPY raw.sales_processed (category, total_quantity, total_revenue, transaction_count, year, month)
    FROM 's3://{bucket}/processed/'
    IAM_ROLE '{role}'
    FORMAT AS PARQUET
""")
print("COPY complete.")
cur.close()
conn.close()
