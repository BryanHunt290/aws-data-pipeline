# IAM roles for Glue and Step Functions

resource "aws_iam_role" "glue" {
  name = "${local.name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "glue-s3-kms"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*",
          aws_s3_bucket.staging.arn,
          "${aws_s3_bucket.staging.arn}/*",
          aws_s3_bucket.athena.arn,
          "${aws_s3_bucket.athena.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.data.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetDatabase",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetPartitions",
          "glue:BatchCreatePartition"
        ]
        Resource = [
          "arn:aws:glue:${local.region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.region}:${local.account_id}:database/${aws_glue_catalog_database.main.name}",
          "arn:aws:glue:${local.region}:${local.account_id}:table/${aws_glue_catalog_database.main.name}/*"
        ]
      }
    ]
  })
}

# Staging bucket for Glue scripts
resource "aws_s3_bucket" "staging" {
  bucket = "${local.prefix}-staging-${local.account_id}-${var.environment}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "staging" {
  bucket = aws_s3_bucket.staging.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.data.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "staging" {
  bucket = aws_s3_bucket.staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
