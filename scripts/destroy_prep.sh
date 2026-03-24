#!/bin/bash
# Pre-destroy cleanup: Athena workgroup + empty S3 buckets
# Handles "WorkGroup is not empty" and "BucketNotEmpty" errors during terraform destroy

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

WORKGROUP="data-pipeline-demo"

# Get bucket names from terraform output, fall back to computing from account ID
# (terraform output fails when resources are partially destroyed)
cd infrastructure/terraform
DATA_BUCKET=$(terraform output -raw s3_bucket 2>/dev/null)
ATHENA_BUCKET=$(terraform output -raw athena_results_bucket 2>/dev/null)
cd "$PROJECT_ROOT"

# Validate bucket names - if they don't look like valid S3 names, compute from account ID
s3_name_valid() { [[ "$1" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; }
if ! s3_name_valid "$DATA_BUCKET" || ! s3_name_valid "$ATHENA_BUCKET"; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  DATA_BUCKET="data-pipeline-demo-${ACCOUNT_ID}"
  ATHENA_BUCKET="data-pipeline-demo-athena-${ACCOUNT_ID}"
fi

# Empty S3 buckets (handles versioned buckets - deletes all versions + delete markers)
empty_bucket() {
  local bucket=$1
  [ -z "$bucket" ] && return
  echo "Emptying S3 bucket $bucket..."
  aws s3 rm "s3://${bucket}/" --recursive 2>/dev/null || true
  # Delete all versions and delete markers (required for versioned buckets)
  aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
    BUCKET_NAME="$bucket" python3 -c "
import json, sys, subprocess, os
bucket = os.environ.get('BUCKET_NAME', '')
if not bucket: sys.exit(0)
try:
  d = json.load(sys.stdin)
  for obj in d.get('Versions', []) + d.get('DeleteMarkers', []):
    cmd = ['aws', 's3api', 'delete-object', '--bucket', bucket, '--key', obj['Key']]
    if obj.get('VersionId'):
      cmd.extend(['--version-id', obj['VersionId']])
    subprocess.run(cmd, capture_output=True)
except: pass
" 2>/dev/null || true
}

empty_bucket "$DATA_BUCKET"
empty_bucket "$ATHENA_BUCKET"

# Delete Athena workgroup (recursive)
echo "Deleting Athena workgroup $WORKGROUP (recursive)..."
if aws athena delete-work-group --work-group "$WORKGROUP" --recursive-delete-option 2>/dev/null; then
  echo "Workgroup deleted. Removing from Terraform state..."
  cd infrastructure/terraform && terraform state rm aws_athena_workgroup.main 2>/dev/null || true
  cd "$PROJECT_ROOT"
fi
