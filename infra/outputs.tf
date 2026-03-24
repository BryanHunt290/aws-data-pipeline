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

output "msk_bootstrap_servers" {
  description = "MSK Serverless bootstrap servers for Kafka clients"
  value       = try(aws_msk_serverless_cluster.main[0].bootstrap_broker_sasl_iam, null)
}

output "msk_cluster_arn" {
  description = "MSK Serverless cluster ARN"
  value       = try(aws_msk_serverless_cluster.main[0].arn, null)
}

output "lambda_trigger_arn" {
  description = "Lambda ARN for S3-triggered batch pipeline"
  value       = aws_lambda_function.trigger_pipeline.arn
}

output "lambda_start_streaming_arn" {
  description = "Lambda ARN to start Glue Streaming job"
  value       = try(aws_lambda_function.start_streaming[0].arn, null)
}
