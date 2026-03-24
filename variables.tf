variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "aws-data-pipeline"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket"
  type        = string
  default     = "mrts-retail-sales-"
}