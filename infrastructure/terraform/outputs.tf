output "s3_bucket" {
  description = "S3 bucket for raw and processed data"
  value       = aws_s3_bucket.data.bucket
}

output "raw_prefix" {
  description = "S3 prefix for raw data"
  value       = "s3://${aws_s3_bucket.data.bucket}/raw/"
}

output "processed_prefix" {
  description = "S3 prefix for processed data"
  value       = "s3://${aws_s3_bucket.data.bucket}/processed/"
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "glue_job_name" {
  description = "Glue ETL job name"
  value       = aws_glue_job.transform.name
}

output "athena_workgroup" {
  description = "Athena workgroup for querying"
  value       = aws_athena_workgroup.main.name
}

output "athena_results_bucket" {
  description = "Athena results bucket"
  value       = aws_s3_bucket.athena.bucket
}

output "glue_database" {
  description = "Glue database name"
  value       = aws_glue_catalog_database.main.name
}

output "redshift_endpoint" {
  description = "Redshift endpoint (when enable_redshift=true)"
  value       = try(aws_redshiftserverless_workgroup.main[0].endpoint[0].address, null)
}

output "redshift_iam_role_arn" {
  description = "Redshift IAM role for COPY"
  value       = try(aws_iam_role.redshift[0].arn, null)
}
