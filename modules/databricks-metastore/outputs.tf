output "metastore_id" {
  description = "ID of the Unity Catalog metastore"
  value       = databricks_metastore.this.id
}
