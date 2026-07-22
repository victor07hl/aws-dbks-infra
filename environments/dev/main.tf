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
