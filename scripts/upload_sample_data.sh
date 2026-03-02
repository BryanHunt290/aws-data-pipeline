#!/bin/bash
# Upload sample data to S3 raw/ folder
# Run from project root after: terraform apply

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BUCKET=$(cd infrastructure/terraform && terraform output -raw s3_bucket 2>/dev/null || echo "")
if [ -z "$BUCKET" ]; then
  echo "Run 'terraform apply' in infrastructure/terraform first"
  exit 1
fi
aws s3 cp data/sample_data.csv "s3://${BUCKET}/raw/sample_data.csv"
echo "Uploaded to s3://${BUCKET}/raw/sample_data.csv"
