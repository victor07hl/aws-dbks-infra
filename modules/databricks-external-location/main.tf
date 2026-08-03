terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.workspace]
    }
  }
}

# Ready-for-use (IT-74): authored + validated, not instantiated in any
# environment root yet. Packages the repeatable "external location covering
# an S3 path" pattern that IT-66 hand-rolled inline for the vicmo catalog
# (databricks_storage_credential.vicmo/databricks_external_location.vicmo in
# environments/dev/main.tf) — those two resources are a candidate to migrate
# into this module via `terraform state mv` in a future ticket, not this one.
#
# AWS-side IAM is out of scope: storage_credential_role_arn (or the existing
# credential referenced via storage_credential_name) must already have S3
# read/write + KMS decrypt on the target path from modules/iam-storage. This
# module only registers a credential/location with Unity Catalog — it grants
# no AWS permissions itself.
#
# Example usage — new bucket path, own storage credential, granted to a group:
#
# module "external_location_reporting" {
#   source = "../../modules/databricks-external-location"
#   providers = {
#     databricks.workspace = databricks.workspace
#   }
#
#   name                        = "dbks-infra-dev-extloc-reporting"
#   s3_url                      = "s3://dbks-infra-dev-s3-ws/unity-catalog/reporting"
#   create_storage_credential   = true
#   storage_credential_name     = "dbks-infra-dev-cred-reporting"
#   storage_credential_role_arn = module.iam_storage.role_arn
#
#   owner_group = "data-engineers"
#   grants      = ["CREATE_EXTERNAL_TABLE", "CREATE_EXTERNAL_VOLUME"]
# }
#
# Example usage — reusing an existing storage credential (default path):
#
# module "external_location_archive" {
#   source = "../../modules/databricks-external-location"
#   providers = {
#     databricks.workspace = databricks.workspace
#   }
#
#   name                    = "dbks-infra-dev-extloc-archive"
#   s3_url                  = "s3://dbks-infra-dev-s3-ws/unity-catalog/archive"
#   storage_credential_name = "dbks-infra-dev-cred-vicmo"
# }

resource "databricks_storage_credential" "this" {
  count    = var.create_storage_credential ? 1 : 0
  provider = databricks.workspace

  name = var.storage_credential_name

  aws_iam_role {
    role_arn = var.storage_credential_role_arn
  }
}

resource "databricks_external_location" "this" {
  provider = databricks.workspace

  name            = var.name
  url             = var.s3_url
  credential_name = var.create_storage_credential ? databricks_storage_credential.this[0].name : var.storage_credential_name
}

resource "databricks_grants" "this" {
  count    = var.owner_group != null ? 1 : 0
  provider = databricks.workspace

  external_location = databricks_external_location.this.name

  grant {
    principal  = var.owner_group
    privileges = var.grants
  }
}
