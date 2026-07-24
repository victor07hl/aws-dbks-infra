terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.account]
    }
  }
}

resource "databricks_mws_credentials" "this" {
  provider = databricks.account

  # account_id is deprecated on this resource specifically — it's sourced
  # from the databricks.account provider's account_id instead.
  credentials_name = var.credential_name
  role_arn         = var.credential_role_arn
}

resource "databricks_mws_networks" "this" {
  provider = databricks.account

  account_id         = var.databricks_account_id
  network_name       = var.network_config_name
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
}

resource "databricks_mws_storage_configurations" "this" {
  provider = databricks.account

  account_id                 = var.databricks_account_id
  storage_configuration_name = var.storage_config_name
  bucket_name                = var.bucket_name
  role_arn                   = var.storage_role_arn
}

# deployment_name intentionally left unset — Databricks generates it, and
# downstream code must read workspace_url rather than hardcode it (see
# Appendix C item 11 in docs/manual-deployment-findings.md).
resource "databricks_mws_workspaces" "this" {
  provider = databricks.account

  account_id     = var.databricks_account_id
  workspace_name = var.workspace_name
  aws_region     = var.region
  pricing_tier   = var.pricing_tier

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id
}

resource "databricks_metastore_assignment" "this" {
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this.workspace_id
  metastore_id = var.metastore_id
}

# Looks up the account-level service principal behind the OAuth M2M
# credentials in Secrets Manager, by application (client) ID.
data "databricks_service_principal" "m2m" {
  provider = databricks.account

  application_id = var.m2m_service_principal_application_id
}

# Grants that same service principal ADMIN at the workspace level so it can
# authenticate against the workspace (not just the account) for the catalog
# story next.
resource "databricks_mws_permission_assignment" "m2m_admin" {
  provider = databricks.account

  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = data.databricks_service_principal.m2m.id
  permissions  = ["ADMIN"]
}
