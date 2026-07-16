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
