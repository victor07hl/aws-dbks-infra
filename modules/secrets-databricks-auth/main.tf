data "aws_caller_identity" "current" {}

resource "aws_kms_key" "secrets" {
  description             = var.kms_description
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIamPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_kms_alias" "secrets" {
  name          = var.kms_alias
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_secretsmanager_secret" "this" {
  name        = var.secret_name
  description = var.secret_description
  kms_key_id  = aws_kms_key.secrets.arn
}

# Placeholder version so the account-level databricks provider's data source
# read never hits a secret with zero versions (would break every plan/apply).
# An operator overwrites this out-of-band after creating the service
# principal; ignore_changes keeps Terraform from reverting that write.
resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    client_id     = "REPLACE_ME"
    client_secret = "REPLACE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
