# Glue Data Catalog, Crawlers, and ETL Job

resource "aws_glue_catalog_database" "main" {
  name        = "${replace(local.prefix, "-", "_")}_${var.environment}_catalog"
  description = "Glue Data Catalog for MRTS retail sales"
}

# Upload Glue ETL script
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.staging.id
  key    = "scripts/mrts_etl.py"
  source = "${path.module}/../etl/mrts_etl.py"
  etag   = filemd5("${path.module}/../etl/mrts_etl.py")
}

# Glue Crawler - Raw data
resource "aws_iam_role" "crawler" {
  name = "${local.name}-crawler-role"

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

resource "aws_iam_role_policy" "crawler" {
  name = "crawler-s3-glue"
  role = aws_iam_role.crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetTable"
        ]
        Resource = [
          "arn:aws:glue:${local.region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.region}:${local.account_id}:database/${aws_glue_catalog_database.main.name}",
          "arn:aws:glue:${local.region}:${local.account_id}:table/${aws_glue_catalog_database.main.name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.data.arn]
      }
    ]
  })
}

resource "aws_glue_crawler" "raw" {
  name          = "${local.name}-crawler-raw"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.main.name

  s3_target {
    path = "s3://${aws_s3_bucket.data.bucket}/raw/retail_sales/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "curated" {
  name          = "${local.name}-crawler-curated"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.main.name

  s3_target {
    path = "s3://${aws_s3_bucket.data.bucket}/curated/retail_sales/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

# Glue ETL Job
resource "aws_glue_job" "mrts_etl" {
  name     = "${local.name}-mrts-etl"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.staging.bucket}/scripts/mrts_etl.py"
    python_version  = "3"
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-glue-datacatalog"          = "true"
    "--RAW_S3_PREFIX"                    = "s3://${aws_s3_bucket.data.bucket}/raw/retail_sales/"
    "--CURATED_S3_PREFIX"                = "s3://${aws_s3_bucket.data.bucket}/curated/retail_sales/"
    "--GLUE_DATABASE"                    = aws_glue_catalog_database.main.name
    "--TABLE_NAME"                      = "retail_sales"
    "--INGEST_DATE"                      = ""
  }

  depends_on = [aws_s3_object.glue_script]
}
