# Redshift Serverless - Data warehouse layer (optional, requires opt-in)
# Set enable_redshift=true and TF_VAR_redshift_admin_password

variable "enable_redshift" {
  description = "Enable Redshift Serverless (requires AWS Console opt-in)"
  type        = bool
  default     = false
}

variable "redshift_admin_password" {
  description = "Redshift admin password (required when enable_redshift=true)"
  type        = string
  sensitive   = true
  default     = ""
}

data "aws_vpc" "redshift" {
  count   = var.enable_redshift ? 1 : 0
  default = true
}

data "aws_subnets" "redshift" {
  count = var.enable_redshift ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.redshift[0].id]
  }
}

resource "aws_iam_role" "redshift" {
  count = var.enable_redshift ? 1 : 0

  name = "${local.name}-redshift"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = ["redshift.amazonaws.com", "redshift-serverless.amazonaws.com"]
      }
    }]
  })
}

resource "aws_iam_role_policy" "redshift_s3" {
  count  = var.enable_redshift ? 1 : 0
  name   = "redshift-s3"
  role   = aws_iam_role.redshift[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
    }]
  })
}

resource "aws_redshiftserverless_namespace" "main" {
  count                = var.enable_redshift ? 1 : 0
  namespace_name       = replace(local.name, "-", "_")
  default_iam_role_arn  = aws_iam_role.redshift[0].arn
  iam_roles            = [aws_iam_role.redshift[0].arn]
  db_name              = "sales"
  admin_username       = "admin"
  admin_user_password  = var.redshift_admin_password
}

resource "aws_redshiftserverless_workgroup" "main" {
  count          = var.enable_redshift ? 1 : 0
  namespace_name = aws_redshiftserverless_namespace.main[0].namespace_name
  workgroup_name = replace(local.name, "-", "_")
  base_capacity  = 8
  publicly_accessible = true
  subnet_ids     = data.aws_subnets.redshift[0].ids
}
