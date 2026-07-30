output "cluster_id" {
  description = "Unique ID of the Databricks cluster"
  value       = one(concat(databricks_cluster.single_node[*].id, databricks_cluster.multi_node[*].id))
}

output "cluster_name" {
  description = "Name of the Databricks cluster"
  value       = one(concat(databricks_cluster.single_node[*].cluster_name, databricks_cluster.multi_node[*].cluster_name))
}
