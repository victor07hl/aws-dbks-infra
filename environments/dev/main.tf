module "network" {
  source = "../../modules/network"

  environment          = var.environment
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "iam_credential" {
  source = "../../modules/iam-credential"

  databricks_account_id = var.databricks_account_id
  role_name             = var.credential_role_name
}

module "s3_workspace" {
  source = "../../modules/s3-workspace"

  bucket_name = var.workspace_bucket_name
}

module "iam_storage" {
  source = "../../modules/iam-storage"

  databricks_account_id = var.databricks_account_id
  role_name             = var.storage_role_name
  bucket_name           = module.s3_workspace.bucket_name
  bucket_arn            = module.s3_workspace.bucket_arn
}

module "secrets_databricks_auth" {
  source = "../../modules/secrets-databricks-auth"

  secret_name = var.databricks_secret_name
  kms_alias   = var.databricks_secret_kms_alias
}

module "databricks_metastore" {
  source = "../../modules/databricks-metastore"
  providers = {
    databricks.account = databricks.account
  }

  metastore_name = var.metastore_name
  region         = var.region
}

module "databricks_workspace" {
  source = "../../modules/databricks-workspace"
  providers = {
    databricks.account = databricks.account
  }

  databricks_account_id = var.databricks_account_id

  credential_name     = var.workspace_credential_name
  credential_role_arn = module.iam_credential.role_arn

  network_config_name = var.workspace_network_config_name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [module.network.security_group_id]

  storage_config_name = var.workspace_storage_config_name
  bucket_name         = module.s3_workspace.bucket_name
  storage_role_arn    = module.iam_storage.role_arn

  workspace_name = var.workspace_name
  region         = var.region
  pricing_tier   = var.workspace_pricing_tier

  metastore_id = module.databricks_metastore.metastore_id

  m2m_service_principal_application_id = local.databricks_m2m_creds.client_id
}

module "databricks_catalog" {
  source = "../../modules/databricks-catalog"
  providers = {
    databricks.workspace = databricks.workspace
  }

  catalog_name   = var.catalog_name
  storage_root   = var.catalog_storage_root
  owner          = var.catalog_owner
  isolation_mode = var.catalog_isolation_mode

  schema_name  = var.catalog_schema_name
  schema_owner = var.catalog_schema_owner

  workspace_id = module.databricks_workspace.workspace_id
}

# Unity Catalog storage credential + external location covering the vicmo
# catalog's schema paths (IT-66). Needed because this metastore has no
# storage_root: any managed storage path used anywhere below it (catalog or
# schema level) must be covered by a registered External Location so UC
# knows which IAM role to assume for reads/writes. Reuses the existing
# self-assuming UC trust role (already scoped to S3 R/W + KMS decrypt on
# /unity-catalog/*) rather than provisioning new IAM. A fuller, reusable
# external-location module is tracked separately as IT-74; this is the
# minimal piece needed to unblock IT-66.
resource "databricks_storage_credential" "vicmo" {
  provider = databricks.workspace

  name = var.catalog_vicmo_storage_credential_name

  aws_iam_role {
    role_arn = module.iam_storage.role_arn
  }
}

resource "databricks_external_location" "vicmo" {
  provider = databricks.workspace

  name            = var.catalog_vicmo_external_location_name
  url             = var.catalog_vicmo_storage_root
  credential_name = databricks_storage_credential.vicmo.name
}

# Project-scoped catalog per naming-conventions.docx's {project_name}
# pattern, with the medallion schema set from docs/folder-structure.md.
# Created alongside module.databricks_catalog (the auto-generated
# dev_<workspace_id> catalog), not instead of it — that one is left as-is
# per IT-66's scope decision (see its variable descriptions above).
#
# storage_root is set to the external location's own base URL: CREATE
# CATALOG requires the catalog to have a managed location of its own
# (confirmed live — "Metastore storage root URL does not exist ... please
# provide a storage location for the catalog"), schema-level storage_root
# alone isn't sufficient. Each schema below still gets its own subpath
# storage_root nested under the catalog's, for per-medallion-layer storage
# governance.
#
# owner is the M2M service principal Terraform already authenticates as
# (same one used everywhere else in this file) rather than an admin group —
# "account admins" (the original assumption) doesn't exist as a principal in
# this account (confirmed live: "Could not find principal with name account
# admins"). Migrate to a proper group once modules/databricks-identity
# (IT-73) is wired into an environment.
module "databricks_catalog_vicmo" {
  source = "../../modules/databricks-catalog"
  providers = {
    databricks.workspace = databricks.workspace
  }

  catalog_name   = var.catalog_vicmo_name
  storage_root   = databricks_external_location.vicmo.url
  owner          = local.databricks_m2m_creds.client_id
  isolation_mode = var.catalog_isolation_mode

  schema_name         = "raw"
  schema_owner        = local.databricks_m2m_creds.client_id
  schema_storage_root = "${databricks_external_location.vicmo.url}/raw"

  additional_schemas = {
    bronze = { owner = local.databricks_m2m_creds.client_id, storage_root = "${databricks_external_location.vicmo.url}/bronze" }
    silver = { owner = local.databricks_m2m_creds.client_id, storage_root = "${databricks_external_location.vicmo.url}/silver" }
    gold   = { owner = local.databricks_m2m_creds.client_id, storage_root = "${databricks_external_location.vicmo.url}/gold" }
    stage  = { owner = local.databricks_m2m_creds.client_id, storage_root = "${databricks_external_location.vicmo.url}/stage" }
  }

  workspace_id = module.databricks_workspace.workspace_id
}

module "databricks_cluster" {
  source = "../../modules/databricks-cluster"
  providers = {
    databricks.workspace = databricks.workspace
  }

  cluster_name            = var.cluster_name
  node_type_id            = var.cluster_node_type_id
  spark_version           = var.cluster_spark_version
  autotermination_minutes = var.cluster_autotermination_minutes
  runtime_engine          = var.cluster_runtime_engine
}

# Identical config to module.databricks_cluster (the "TEST" cluster) —
# reuses the same node_type_id/spark_version/autotermination_minutes/
# runtime_engine variables so "identical" stays a single source of truth
# rather than two copies that can drift apart (IT-88).
module "databricks_cluster_dev_admin" {
  source = "../../modules/databricks-cluster"
  providers = {
    databricks.workspace = databricks.workspace
  }

  cluster_name            = var.cluster_dev_admin_name
  node_type_id            = var.cluster_node_type_id
  spark_version           = var.cluster_spark_version
  autotermination_minutes = var.cluster_autotermination_minutes
  runtime_engine          = var.cluster_runtime_engine
}
