# IT-62: brownfield import of the workspace-level Databricks pieces created
# manually in docs/manual-deployment-findings.md Parts 5-8. Live names/IDs
# confirmed via the account API — do not trust Appendix A blindly (workspace
# name there is wrong: live value is "DEV", not "dbks-infra-dev-ws", same
# drift class as the IT-61 metastore-name lesson).
#
# Remove this file once `terraform apply` has bound all four resources into
# state (import blocks are one-time; leaving it is harmless but unnecessary).

import {
  to = module.databricks_workspace.databricks_mws_credentials.this
  id = "${var.databricks_account_id}/65062cd0-2d85-4a74-8eae-2ee1f26b8f18"
}

import {
  to = module.databricks_workspace.databricks_mws_networks.this
  id = "${var.databricks_account_id}/5eef829c-4138-4584-a4c0-584fd3fa82ce"
}

import {
  to = module.databricks_workspace.databricks_mws_storage_configurations.this
  id = "${var.databricks_account_id}/7ab6d24c-6b88-4587-b869-f84715f2d3ee"
}

import {
  to = module.databricks_workspace.databricks_mws_workspaces.this
  id = "${var.databricks_account_id}/7474644050018837"
}
