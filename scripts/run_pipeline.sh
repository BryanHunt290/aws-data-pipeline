#!/bin/bash
# Start the Step Functions pipeline
# Run from project root after: terraform apply

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

ARN=$(cd infrastructure/terraform && terraform output -raw state_machine_arn 2>/dev/null || echo "")
if [ -z "$ARN" ]; then
  echo "Run 'terraform apply' in infrastructure/terraform first"
  exit 1
fi
aws stepfunctions start-execution --state-machine-arn "$ARN"
echo "Pipeline started. Check Step Functions console for status."
