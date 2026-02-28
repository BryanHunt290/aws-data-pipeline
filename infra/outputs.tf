output "data_bucket" {
  description = "S3 bucket for raw and curated data"
  value       = aws_s3_bucket.data.bucket
}

output "raw_prefix" {
  description = "S3 prefix for raw data"
  value       = "s3://${aws_s3_bucket.data.bucket}/raw/retail_sales/"
}

output "curated_prefix" {
  description = "S3 prefix for curated Parquet"
  value       = "s3://${aws_s3_bucket.data.bucket}/curated/retail_sales/"
}

output "glue_database" {
  description = "Glue Data Catalog database"
  value       = aws_glue_catalog_database.main.name
}

output "glue_job_name" {
  description = "Glue ETL job name"
  value       = aws_glue_job.mrts_etl.name
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.main.name
}

output "athena_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena.bucket
}
