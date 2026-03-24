# Athena - Query S3/Glue when Redshift is disabled (fallback for dashboard)

resource "aws_s3_bucket" "athena" {
  bucket        = "${local.name}-athena-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "athena" {
  bucket = aws_s3_bucket.athena.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "main" {
  name          = local.name
  force_destroy = true
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

# Pre-create Glue table so Athena can query before crawler runs
# Crawler will update schema when it runs
resource "aws_glue_catalog_table" "processed" {
  name          = "processed"
  database_name = aws_glue_catalog_database.main.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data.bucket}/processed/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "category"
      type = "string"
    }
    columns {
      name = "total_quantity"
      type = "bigint"
    }
    columns {
      name = "total_revenue"
      type = "double"
    }
    columns {
      name = "transaction_count"
      type = "bigint"
    }
    columns {
      name = "year"
      type = "int"
    }
    columns {
      name = "month"
      type = "int"
    }
  }
}

# --- Keepa raw JSONL external table ---
resource "aws_glue_catalog_table" "keepa_raw" {
  name          = "keepa_raw"
  database_name = aws_glue_catalog_database.main.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                         = "TRUE"
    "projection.enabled"              = "true"
    "projection.ingest_date.type"     = "date"
    "projection.ingest_date.format"   = "yyyy-MM-dd"
    "projection.ingest_date.range"    = "2024-01-01,NOW"
  }

  partition_keys {
    name = "ingest_date"
    type = "date"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data.bucket}/keepa/raw/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "OpenXJsonSerDe"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "asin"
      type = "string"
    }
    columns {
      name = "buy_box_price"
      type = "double"
    }
    columns {
      name = "sales_rank"
      type = "bigint"
    }
    columns {
      name = "offer_count"
      type = "bigint"
    }
    columns {
      name = "captured_at"
      type = "string"
    }
  }
}
