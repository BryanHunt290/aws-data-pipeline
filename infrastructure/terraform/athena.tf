# Athena - Query S3/Glue when Redshift is disabled (fallback for dashboard)

resource "aws_s3_bucket" "athena" {
  bucket = "${local.name}-athena-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "athena" {
  bucket = aws_s3_bucket.athena.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "main" {
  name = local.name
  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena.bucket}/results/"
    }
  }
}

resource "aws_iam_role" "crawler" {
  name = "${local.name}-crawler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "crawler" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "crawler" {
  name   = "crawler-s3-glue"
  role   = aws_iam_role.crawler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["glue:CreateTable", "glue:UpdateTable", "glue:GetTable", "glue:GetDatabase"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_glue_crawler" "processed" {
  name          = "${local.name}-crawler-processed"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.main.name

  s3_target {
    path = "s3://${aws_s3_bucket.data.bucket}/processed/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}
