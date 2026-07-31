output "policy_id" {
  description = "Unique ID of the Databricks cluster policy, consumable by modules/databricks-cluster's policy_id input"
  value       = databricks_cluster_policy.this.id
}
