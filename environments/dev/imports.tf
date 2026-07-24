# IT-63: brownfield import of the catalog-level Databricks pieces. Live
# names confirmed via the workspace-level Unity Catalog REST API — do not
# trust docs/folder-structure.md or Appendix A blindly (there is no
# "dbks-infra-dev-cat"; the live catalog is Unity Catalog's auto-generated
# default "dev_7474644050018837", and only the "default"/"information_schema"
# schemas exist — the raw/bronze/silver/gold/stage medallion schemas were
# never actually created).
#
# Remove this file once `terraform apply` has bound all three resources into
# state (import blocks are one-time; leaving it is harmless but unnecessary).

import {
  to = module.databricks_catalog.databricks_catalog.this
  id = "dev_7474644050018837"
}

import {
  to = module.databricks_catalog.databricks_schema.default
  id = "dev_7474644050018837.default"
}

import {
  to = module.databricks_catalog.databricks_workspace_binding.this
  id = "7474644050018837|catalog|dev_7474644050018837"
}
