# Glue Streaming - Spark Structured Streaming from Kafka to S3
# Requires MSK (enable_msk=true). Glue runs in VPC to reach MSK.

# Security group for Glue (outbound to MSK)
resource "aws_security_group" "glue_streaming" {
  count       = var.enable_msk ? 1 : 0
  name        = "${local.name}-glue-streaming"
  description = "Glue Streaming job - access to MSK"
  vpc_id      = data.aws_vpc.default[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-glue-streaming"
  }
}

# Glue Kafka connection (VPC + bootstrap servers)
resource "aws_glue_connection" "kafka" {
  count = var.enable_msk ? 1 : 0

  connection_properties = {
    KAFKA_BOOTSTRAP_SERVERS = aws_msk_serverless_cluster.main[0].bootstrap_broker_sasl_iam
  }

  name = "${replace(local.name, "-", "_")}_kafka"

  physical_connection_requirements {
    subnet_id             = tolist(data.aws_subnets.default[0].ids)[0]
    security_group_id_list = [aws_security_group.glue_streaming[0].id]
  }
}

# Upload Glue Streaming script
resource "aws_s3_object" "glue_streaming_script" {
  count   = var.enable_msk ? 1 : 0
  bucket  = aws_s3_bucket.staging.id
  key     = "scripts/mrts_streaming.py"
  source  = "${path.module}/../etl/mrts_streaming.py"
  etag    = filemd5("${path.module}/../etl/mrts_streaming.py")
}

# Glue Streaming job (Spark Structured Streaming)
resource "aws_glue_job" "mrts_streaming" {
  count = var.enable_msk ? 1 : 0

  name     = "${local.name}-mrts-streaming"
  role_arn = aws_iam_role.glue.arn

  command {
    name            = "gluestreaming"
    script_location = "s3://${aws_s3_bucket.staging.bucket}/scripts/mrts_streaming.py"
    python_version  = "3"
  }

  glue_version = "4.0"

  worker_type       = "G.1X"
  number_of_workers = 2

  connections = [aws_glue_connection.kafka[0].name]

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-glue-datacatalog"          = "true"
    "--KAFKA_CONNECTION_NAME"            = aws_glue_connection.kafka[0].name
    "--KAFKA_TOPIC"                      = "retail_sales"
    "--CURATED_S3_PREFIX"                = "s3://${aws_s3_bucket.data.bucket}/curated/retail_sales_streaming/"
    "--GLUE_DATABASE"                    = aws_glue_catalog_database.main.name
    "--TABLE_NAME"                       = "retail_sales_streaming"
    "--checkpointLocation"                = "s3://${aws_s3_bucket.staging.bucket}/checkpoints/streaming/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  depends_on = [aws_s3_object.glue_streaming_script]
}
