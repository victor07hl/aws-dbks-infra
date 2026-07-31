output "user_ids" {
  description = "Map of user key (from var.users) to Databricks user ID"
  value       = { for k, v in databricks_user.this : k => v.id }
}

output "group_ids" {
  description = "Map of group key (from var.groups) to Databricks group ID"
  value       = { for k, v in databricks_group.this : k => v.id }
}

output "service_principal_ids" {
  description = "Map of service principal key (from var.service_principals) to Databricks service principal ID"
  value       = { for k, v in databricks_service_principal.this : k => v.id }
}
