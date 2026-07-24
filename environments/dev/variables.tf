variable "environment" {
  description = "Environment name, used in default_tags and resource naming"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region the network resources are deployed into"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones used by the subnets, e.g. [\"us-east-2a\", \"us-east-2b\"]"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnet(s)"
  type        = list(string)
  default     = ["10.0.0.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "databricks_account_id" {
  description = "Databricks account ID, used as the sts:ExternalId condition on cross-account trust policies"
  type        = string
  default     = "c20bd1a1-9022-4ee1-9b47-c91f3ddd7245"
}

variable "credential_role_name" {
  description = "Name of the Databricks cross-account credential IAM role"
  type        = string
  default     = "dbks-infra-dev-ws-role"
}

variable "storage_role_name" {
  description = "Name of the Unity Catalog self-assuming storage trust role"
  type        = string
  default     = "dbks-dev-trust-role-ws"
}

variable "workspace_bucket_name" {
  description = "Name of the per-environment workspace S3 bucket"
  type        = string
  default     = "dbks-infra-dev-s3-ws"
}

variable "databricks_secret_name" {
  description = "Name of the Secrets Manager secret holding the Databricks OAuth M2M service-principal credentials"
  type        = string
  default     = "dbks-infra-dev-sm-databricks-m2m"
}

variable "databricks_secret_kms_alias" {
  description = "Alias of the CMK used to encrypt the Databricks OAuth M2M secret"
  type        = string
  default     = "alias/dbks-infra-dev-kms-sm"
}

variable "metastore_name" {
  description = "Name of the shared Unity Catalog metastore (account-level, no storage_root)"
  type        = string
  default     = "dbks-infra-meta-us2"
}

variable "workspace_credential_name" {
  description = "Name of the Databricks credential configuration"
  type        = string
  default     = "dev-ws-cloud-credential"
}

variable "workspace_network_config_name" {
  description = "Name of the Databricks network configuration"
  type        = string
  default     = "dbks-infra-dev-network-config"
}

variable "workspace_storage_config_name" {
  description = "Name of the Databricks storage configuration"
  type        = string
  default     = "dev-ws-storage"
}

variable "workspace_name" {
  description = "Name of the Databricks workspace (live value is \"DEV\", not \"dbks-infra-dev-ws\" as docs/manual-deployment-findings.md Appendix A claims — confirmed via account API during IT-62, same drift class as the IT-61 metastore-name lesson)"
  type        = string
  default     = "DEV"
}

variable "workspace_pricing_tier" {
  description = "Databricks pricing tier (PREMIUM required for Unity Catalog)"
  type        = string
  default     = "PREMIUM"
}

variable "workspace_network_security_group_ids" {
  description = <<-EOT
    Security group ID(s) the live Databricks network configuration actually
    references. Deliberately NOT module.network.security_group_id: the live
    network config was built against the VPC's default SG (drift from the
    intended dedicated workspace SG, confirmed live during IT-62). Changing
    this value forces destroy+recreate of the network config attached to a
    running workspace, which databricks_mws_networks doesn't support as an
    in-place update — do not "fix" this here; migrate deliberately via a
    follow-up ticket instead.
  EOT
  type        = list(string)
  default     = ["sg-042bea1eb2be1eaa8"]
}
