#!/bin/bash
# Verify pipeline state: raw data, processed data, Glue job status
# Run from project root

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BUCKET=$(cd infrastructure/terraform && terraform output -raw s3_bucket 2>/dev/null || echo "")
GLUE_JOB=$(cd infrastructure/terraform && terraform output -raw glue_job_name 2>/dev/null || echo "")

if [ -z "$BUCKET" ]; then
  echo "❌ Run 'make deploy' first (terraform apply)"
  exit 1
fi

echo "=== Pipeline Verification ==="
echo "Bucket: $BUCKET"
echo ""

# 1. Raw data
RAW_COUNT=$(aws s3 ls "s3://${BUCKET}/raw/" 2>/dev/null | wc -l)
if [ "$RAW_COUNT" -eq 0 ]; then
  echo "❌ Raw data: EMPTY - Run 'make upload' first"
  echo "   → aws s3 cp data/sample_data.csv s3://${BUCKET}/raw/"
else
  echo "✅ Raw data: $(aws s3 ls s3://${BUCKET}/raw/)"
fi

# 2. Processed data
PROC_COUNT=$(aws s3 ls "s3://${BUCKET}/processed/" 2>/dev/null | wc -l)
if [ "$PROC_COUNT" -eq 0 ]; then
  echo "❌ Processed data: EMPTY - Run pipeline after uploading raw data"
  echo "   → make upload && make run"
else
  echo "✅ Processed data: $(aws s3 ls s3://${BUCKET}/processed/ 2>/dev/null | head -5)"
  if [ "$PROC_COUNT" -gt 5 ]; then
    echo "   ... ($PROC_COUNT items)"
  fi
fi

# 3. Glue job last run
if [ -n "$GLUE_JOB" ]; then
  LAST_RUN=$(aws glue get-job-runs --job-name "$GLUE_JOB" --max-items 1 --query 'JobRuns[0].{State:JobRunState,StartedOn:StartedOn}' --output table 2>/dev/null || echo "")
  if [ -n "$LAST_RUN" ]; then
    echo ""
    echo "Glue job last run:"
    echo "$LAST_RUN"
  fi
fi

echo ""
echo "=== Correct order ==="
echo "1. make upload     # Put sample_data.csv in S3 raw/"
echo "2. make run        # Start Step Functions pipeline (wait ~2-3 min)"
echo "3. make crawler    # Run Glue Crawler (wait ~1-2 min)"
echo "4. make dashboard  # View charts"
