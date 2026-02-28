# DE Zoomcamp MRTS - Terraform Infrastructure
# Athena + EventBridge -> Step Functions -> Glue ETL
# Naming matches existing: data-pipeline-tf, athena.tf, stepfunctions.tf

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mrts-retail-sales"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  prefix     = "mrts-retail-sales"
  name       = "${local.prefix}-${var.environment}"
}
