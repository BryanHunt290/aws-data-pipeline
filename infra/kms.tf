# KMS key for encryption at rest
resource "aws_kms_key" "data" {
  description             = "Encryption key for MRTS retail sales pipeline"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.data.key_id
}
