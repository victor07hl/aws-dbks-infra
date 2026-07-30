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
# instead of setting them explicitly, matching how the live cluster was
# created manually via Compute -> Create cluster in the workspace UI.
resource "databricks_cluster" "this" {
  provider = databricks.workspace

  cluster_name            = var.cluster_name
  node_type_id            = var.node_type_id
  spark_version           = var.spark_version
  autotermination_minutes = var.autotermination_minutes
  runtime_engine          = var.runtime_engine

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
