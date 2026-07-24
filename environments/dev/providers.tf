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

# host is a plain variable defaulted to the already-known live workspace URL,
# not derived from databricks_mws_workspaces.this.workspace_url — a provider
# block can't depend on a not-yet-known resource attribute, and it's moot
# anyway since we're importing an already-running workspace (IT-63). Same
# service-principal credentials as the account-level provider; it has
# workspace ADMIN via module.databricks_workspace's permission assignment.
provider "databricks" {
  alias = "workspace"

  host = var.workspace_host

  client_id     = local.databricks_m2m_creds.client_id
  client_secret = local.databricks_m2m_creds.client_secret
}
