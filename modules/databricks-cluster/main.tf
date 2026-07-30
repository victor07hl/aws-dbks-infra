terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.workspace]
    }
  }
}

# Simplified single-node cluster (kind = "CLASSIC_PREVIEW"): is_single_node
# makes Databricks auto-populate custom_tags, spark_conf, and num_workers
# instead of setting them explicitly, matching how the TEST/dev_admin
# clusters were created manually via Compute -> Create cluster in the
# workspace UI (IT-70/IT-88).
#
# Split into two resources (rather than one resource with conditional
# arguments) because lifecycle.ignore_changes below must be a static list -
# it cannot be conditioned on var.is_single_node - so the single-node-only
# ignore_changes rule has to live on a resource that only single-node
# clusters use (IT-71).
resource "databricks_cluster" "single_node" {
  count = var.is_single_node ? 1 : 0

  provider = databricks.workspace

  cluster_name            = var.cluster_name
  node_type_id            = var.node_type_id
  spark_version           = var.spark_version
  autotermination_minutes = var.autotermination_minutes
  runtime_engine          = var.runtime_engine
  policy_id               = var.policy_id

  is_single_node = true
  kind           = "CLASSIC_PREVIEW"

  aws_attributes {
    zone_id = "auto"
  }

  # custom_tags/spark_conf are platform-managed for single-node clusters
  # (ResourceClass=SingleNode tag, spark.master core count derived from
  # node_type_id) but aren't marked Computed in the provider schema, so an
  # unset config would otherwise plan to null them out on every apply.
  lifecycle {
    ignore_changes = [custom_tags, spark_conf]
  }
}

# Multi-worker cluster: UC access mode is caller-controlled (SINGLE_USER or
# USER_ISOLATION, per docs/naming-conventions.docx's UC requirements) since
# there's no platform auto-management to defer to here, unlike single-node.
resource "databricks_cluster" "multi_node" {
  count = var.is_single_node ? 0 : 1

  provider = databricks.workspace

  cluster_name            = var.cluster_name
  node_type_id            = var.node_type_id
  spark_version           = var.spark_version
  autotermination_minutes = var.autotermination_minutes
  runtime_engine          = var.runtime_engine
  policy_id               = var.policy_id
  data_security_mode      = var.data_security_mode

  autoscale {
    min_workers = var.autoscale_min
    max_workers = var.autoscale_max
  }
}
