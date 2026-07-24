output "workspace_id" {
  description = "ID of the Databricks workspace"
  value       = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  description = "URL of the Databricks workspace (deployment name is Databricks-generated, never hardcode it)"
  value       = databricks_mws_workspaces.this.workspace_url
}

output "credentials_id" {
  description = "ID of the Databricks credential configuration"
  value       = databricks_mws_credentials.this.credentials_id
}

output "network_id" {
  description = "ID of the Databricks network configuration"
  value       = databricks_mws_networks.this.network_id
}

output "storage_configuration_id" {
  description = "ID of the Databricks storage configuration"
  value       = databricks_mws_storage_configurations.this.storage_configuration_id
}
