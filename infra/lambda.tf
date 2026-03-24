# Lambda - S3 trigger (start batch pipeline), manual triggers, streaming job start

data "archive_file" "lambda_trigger" {
  type        = "zip"
  output_path = "${path.module}/lambda_trigger.zip"

  source {
    content  = <<-EOF
import json
import boto3

def lambda_handler(event, context):
    client = boto3.client("stepfunctions")
    sm_arn = "${aws_sfn_state_machine.pipeline.arn}"
    client.start_execution(stateMachineArn=sm_arn)
    return {"statusCode": 200, "body": "Pipeline started"}
EOF
    filename = "index.py"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name   = "lambda-stepfunctions"
  role   = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.pipeline.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "trigger_pipeline" {
  filename         = data.archive_file.lambda_trigger.output_path
  function_name    = "${local.name}-trigger"
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_trigger.output_base64sha256
  runtime          = "python3.12"
}

# S3 trigger: when CSV/TXT lands in raw/retail_sales/, start pipeline
resource "aws_s3_bucket_notification" "raw_trigger" {
  bucket = aws_s3_bucket.data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger_pipeline.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/retail_sales/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger_pipeline.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/retail_sales/"
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_pipeline.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data.arn
}

# Lambda: Start Glue Streaming job (for manual/EventBridge trigger)
data "archive_file" "lambda_streaming" {
  count       = var.enable_msk ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_streaming.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os

def lambda_handler(event, context):
    client = boto3.client("glue")
    job_name = os.environ.get("GLUE_STREAMING_JOB", "")
    if not job_name:
        return {"statusCode": 500, "body": "GLUE_STREAMING_JOB not set"}
    client.start_job_run(JobName=job_name)
    return {"statusCode": 200, "body": "Streaming job started"}
EOF
    filename = "index.py"
  }
}

resource "aws_iam_role_policy" "lambda_glue" {
  count  = var.enable_msk ? 1 : 0
  name   = "lambda-glue"
  role   = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "glue:StartJobRun"
      Resource = aws_glue_job.mrts_streaming[0].arn
    }]
  })
}

resource "aws_lambda_function" "start_streaming" {
  count            = var.enable_msk ? 1 : 0
  filename         = data.archive_file.lambda_streaming[0].output_path
  function_name    = "${local.name}-start-streaming"
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_streaming[0].output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      GLUE_STREAMING_JOB = aws_glue_job.mrts_streaming[0].name
    }
  }
}
