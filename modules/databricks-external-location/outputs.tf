output "external_location_id" {
  description = "Unique ID of the Unity Catalog external location"
  value       = databricks_external_location.this.id
}

output "external_location_url" {
  description = "S3 base URL registered for this external location"
  value       = databricks_external_location.this.url
}
