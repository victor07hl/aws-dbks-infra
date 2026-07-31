terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.workspace]
    }
  }
}

# Ready-for-use (IT-72): authored + validated, not instantiated in any
# environment root yet. Example usage once a concrete policy is needed:
#
# module "databricks_cluster_policy_standard" {
#   source = "../../modules/databricks-cluster-policy"
#   providers = {
#     databricks.workspace = databricks.workspace
#   }
#
#   policy_name = "standard-single-node"
#   definition = jsonencode({
#     "node_type_id" : { "type" : "allowlist", "values" : ["m5.large", "m5.xlarge"] }
#     "autotermination_minutes" : { "type" : "range", "minValue" : 10, "maxValue" : 60, "defaultValue" : 20 }
#     "spark_version" : { "type" : "regex", "pattern" : "1[0-9]\\..*" }
#   })
#   max_clusters_per_user = 2
# }
#
# The resulting policy_id output feeds modules/databricks-cluster's
# policy_id input to attach the policy to a cluster.
resource "databricks_cluster_policy" "this" {
  provider = databricks.workspace

  name                  = var.policy_name
  definition            = var.definition
  max_clusters_per_user = var.max_clusters_per_user
}
