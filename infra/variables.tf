variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "enable_msk" {
  description = "Enable MSK Serverless (Kafka) for streaming"
  type        = bool
  default     = true
}
