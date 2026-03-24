# Athena workgroup for querying curated data
resource "aws_athena_workgroup" "main" {
  name = local.name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn      = aws_kms_key.data.arn
      }
    }
  }
}
