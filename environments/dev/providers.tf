provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project     = "aws-dbks-infra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Populated out-of-band after the manual service-principal bootstrap in
# docs/terraform-setup-aws.md Part 9. Reads the placeholder value from
# modules/secrets-databricks-auth until then — harmless since no Databricks
# resource references this provider yet.
data "aws_secretsmanager_secret_version" "databricks_m2m" {
  secret_id = module.secrets_databricks_auth.secret_arn
}

locals {
  databricks_m2m_creds = jsondecode(data.aws_secretsmanager_secret_version.databricks_m2m.secret_string)
}

provider "databricks" {
  alias = "account"

  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id

  client_id     = local.databricks_m2m_creds.client_id
  client_secret = local.databricks_m2m_creds.client_secret
}
