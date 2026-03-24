#!/bin/bash
# Start the Step Functions pipeline
# Run from project root after: terraform apply

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

TF_DIR="$PROJECT_ROOT/infrastructure/terraform"
ARN=$(cd "$TF_DIR" && terraform output -raw state_machine_arn 2>/dev/null || true)
# Output may be missing until `terraform apply` after adding the output; fall back to state / AWS
if [ -z "$ARN" ] || [[ "$ARN" != arn:aws:* ]]; then
  ARN=$(cd "$TF_DIR" && terraform state show -json 'aws_sfn_state_machine.pipeline' 2>/dev/null | jq -r '.values.arn' 2>/dev/null)
fi
if [ -z "$ARN" ] || [[ "$ARN" != arn:aws:* ]]; then
  ARN=$(cd "$TF_DIR" && terraform state show -no-color 'aws_sfn_state_machine.pipeline' 2>/dev/null | sed -n 's/^[[:space:]]*arn[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' | head -1)
fi
if [ -z "$ARN" ] || [[ "$ARN" != arn:aws:* ]]; then
  REGION=$(cd "$TF_DIR" && terraform output -raw aws_region 2>/dev/null || aws configure get region || echo "us-east-1")
  ARN=$(aws stepfunctions list-state-machines --region "$REGION" --query "stateMachines[?name=='data-pipeline-demo'].stateMachineArn" --output text 2>/dev/null || true)
fi
if [ -z "$ARN" ] || [[ "$ARN" != arn:aws:* ]]; then
  echo "Could not resolve Step Functions ARN. Run 'make deploy' in infrastructure/terraform first."
  echo "If outputs are stale: cd infrastructure/terraform && terraform apply"
  exit 1
fi
aws stepfunctions start-execution --state-machine-arn "$ARN"
echo "Pipeline started. Check Step Functions console for status."
