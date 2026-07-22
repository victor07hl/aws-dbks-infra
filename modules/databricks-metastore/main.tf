terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.account]
    }
  }
}

# No storage_root (project decision, see CLAUDE.md) — UC managed data lands
# in each workspace's own S3 bucket under /unity-catalog/*, not a
# metastore-level bucket.
resource "databricks_metastore" "this" {
  provider = databricks.account

  name                                              = var.metastore_name
  region                                            = var.region
  delta_sharing_scope                               = var.delta_sharing_scope
  delta_sharing_recipient_token_lifetime_in_seconds = var.delta_sharing_recipient_token_lifetime_in_seconds
  force_destroy                                     = var.force_destroy
}
