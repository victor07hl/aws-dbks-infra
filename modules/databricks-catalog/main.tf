terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.workspace]
    }
  }
}

# catalog_type is computed (MANAGED_CATALOG), not a settable argument.
resource "databricks_catalog" "this" {
  provider = databricks.workspace

  name                           = var.catalog_name
  storage_root                   = var.storage_root
  owner                          = var.owner
  isolation_mode                 = var.isolation_mode
  enable_predictive_optimization = var.enable_predictive_optimization
}

resource "databricks_schema" "default" {
  provider = databricks.workspace

  name                           = var.schema_name
  catalog_name                   = databricks_catalog.this.name
  owner                          = var.schema_owner
  comment                        = var.schema_comment
  enable_predictive_optimization = var.schema_enable_predictive_optimization
}

resource "databricks_schema" "additional" {
  for_each = var.additional_schemas
  provider = databricks.workspace

  name                           = each.key
  catalog_name                   = databricks_catalog.this.name
  owner                          = each.value.owner
  comment                        = each.value.comment
  enable_predictive_optimization = each.value.enable_predictive_optimization
}

resource "databricks_workspace_binding" "this" {
  provider = databricks.workspace

  workspace_id   = var.workspace_id
  securable_name = databricks_catalog.this.name
  securable_type = "catalog"
  binding_type   = var.binding_type
}
