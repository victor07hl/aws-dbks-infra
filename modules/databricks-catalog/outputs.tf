output "catalog_name" {
  description = "Name of the Unity Catalog catalog"
  value       = databricks_catalog.this.name
}

output "catalog_id" {
  description = "Unique ID of the Unity Catalog catalog"
  value       = databricks_catalog.this.id
}

output "schema_full_name" {
  description = "Full name of the schema (<catalog_name>.<schema_name>)"
  value       = databricks_schema.default.id
}

output "additional_schema_full_names" {
  description = "Map of additional schema name -> full name (<catalog_name>.<schema_name>), for schemas created via additional_schemas"
  value       = { for k, v in databricks_schema.additional : k => v.id }
}
