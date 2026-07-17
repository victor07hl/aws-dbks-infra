output "secret_arn" {
  description = "ARN of the Databricks OAuth M2M secret"
  # Sourced from the version resource (same ARN as the secret itself) so
  # consumers reading this via a data source implicitly depend on the
  # placeholder version existing first — otherwise Terraform has no edge
  # forcing the version to be created before a same-apply data source read,
  # which fails with "couldn't find resource" on a brand-new secret.
  value = aws_secretsmanager_secret_version.this.arn
}

output "secret_name" {
  description = "Name of the Databricks OAuth M2M secret"
  value       = aws_secretsmanager_secret.this.name
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting the secret"
  value       = aws_kms_key.secrets.arn
}
