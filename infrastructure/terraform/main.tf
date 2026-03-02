# Minimal AWS Data Pipeline - S3, Glue, Lambda, Step Functions
# Free tier friendly, portfolio demo

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  name       = "data-pipeline-demo"
}

# --- S3 ---
resource "aws_s3_bucket" "data" {
  bucket = "${local.name}-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Glue ---
resource "aws_glue_catalog_database" "main" {
  name = "${replace(local.name, "-", "_")}_catalog"
}

resource "aws_iam_role" "glue" {
  name = "${local.name}-glue"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name   = "glue-s3"
  role   = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
    }]
  })
}

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${local.name}-scripts-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/transform_job.py"
  source = "${path.module}/../../glue/transform_job.py"
  etag   = filemd5("${path.module}/../../glue/transform_job.py")
}

resource "aws_glue_job" "transform" {
  name     = "${local.name}-transform"
  role_arn = aws_iam_role.glue.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/transform_job.py"
    python_version  = "3"
  }
  glue_version     = "4.0"
  worker_type      = "G.1X"
  number_of_workers = 2
  default_arguments = {
    "--job-language"               = "python"
    "--job-bookmark-option"        = "job-bookmark-disable"
    "--enable-glue-datacatalog"   = "true"
    "--INPUT_PATH"                 = "s3://${aws_s3_bucket.data.bucket}/raw/"
    "--OUTPUT_PATH"                = "s3://${aws_s3_bucket.data.bucket}/processed/"
  }
  depends_on = [aws_s3_object.glue_script]
}

# --- Lambda ---
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"
  source {
    content  = file("${path.module}/../../lambda/trigger_glue.py")
    filename = "trigger_glue.py"
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
  name   = "lambda-glue"
  role   = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "glue:StartJobRun"
        Resource = aws_glue_job.transform.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "trigger_glue" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${local.name}-trigger"
  role             = aws_iam_role.lambda.arn
  handler          = "trigger_glue.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime          = "python3.12"
  environment {
    variables = {
      GLUE_JOB_NAME = aws_glue_job.transform.name
    }
  }
}

# --- Step Functions ---
resource "aws_iam_role" "stepfunctions" {
  name = "${local.name}-stepfunctions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "stepfunctions" {
  name   = "stepfunctions"
  role   = aws_iam_role.stepfunctions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "glue:StartJobRun"
        Resource = aws_glue_job.transform.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = local.name
  role_arn = aws_iam_role.stepfunctions.arn
  definition = jsonencode({
    Comment = "Data pipeline: Step Functions starts Glue job and waits for completion"
    StartAt = "GlueETL"
    States = {
      GlueETL = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.transform.name
        }
        End = true
      }
    }
  })
}
