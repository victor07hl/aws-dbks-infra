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

variable "workspace_host" {
  description = "URL of the live Databricks workspace, used by the workspace-level provider (IT-63)"
  type        = string
  default     = "https://dbc-03363fa1-0d7a.cloud.databricks.com"
}

variable "catalog_name" {
  description = <<-EOT
    Name of the Unity Catalog catalog. Live value is "dev_7474644050018837" —
    Unity Catalog's auto-generated default catalog (<workspace_name>_<workspace_id>).
    docs/folder-structure.md's "dbks-infra-dev-cat" was never actually created
    (confirmed live during IT-63); adopting the auto-generated catalog as-is
    rather than creating a new project-named one is a deliberate scope
    decision for this ticket.
  EOT
  type        = string
  default     = "dev_7474644050018837"
}

variable "catalog_storage_root" {
  description = "S3 path backing the catalog's managed data"
  type        = string
  default     = "s3://dbks-infra-dev-s3-ws/unity-catalog/7474644050018837"
}

variable "catalog_owner" {
  description = "Owner principal of the catalog (Databricks-assigned default admin group for this catalog)"
  type        = string
  default     = "_workspace_admins_dev_7474644050018837"
}

variable "catalog_isolation_mode" {
  description = "Catalog isolation mode: OPEN or ISOLATED"
  type        = string
  default     = "ISOLATED"
}

variable "catalog_schema_name" {
  description = "Name of the schema being managed within the catalog"
  type        = string
  default     = "default"
}

variable "catalog_schema_owner" {
  description = "Owner principal of the schema"
  type        = string
  default     = "_workspace_admins_dev_7474644050018837"
}

variable "catalog_vicmo_name" {
  description = "Name of the project-scoped Unity Catalog catalog, per naming-conventions.docx's {project_name} pattern (lowercase, no hyphens/underscores) (IT-66). Created alongside, not instead of, the pre-existing auto-generated catalog_name catalog — that one is left as-is per IT-66's scope decision."
  type        = string
  default     = "vicmo"
}

variable "catalog_vicmo_storage_root" {
  description = "S3 path backing the vicmo catalog's managed data"
  type        = string
  default     = "s3://dbks-infra-dev-s3-ws/unity-catalog/vicmo"
}

variable "catalog_vicmo_owner" {
  description = "Owner principal of the vicmo catalog and its schemas. Unlike the auto-generated catalog (which gets a Databricks-assigned per-catalog admin group), this is a freshly created catalog, so it defaults to the built-in account-level \"account admins\" group rather than a group that doesn't exist yet."
  type        = string
  default     = "account admins"
}

variable "cluster_name" {
  description = "Name of the Databricks cluster. Live value is \"TEST\" - created manually via Compute -> Create cluster as the smoke-test single-node cluster from docs/manual-deployment-findings.md, brought under Terraform via import (IT-70)"
  type        = string
  default     = "TEST"
}

variable "cluster_node_type_id" {
  description = "AWS instance type for the single-node cluster (confirmed live via `databricks clusters get`)"
  type        = string
  default     = "m5d.large"
}

variable "cluster_spark_version" {
  description = "Databricks Runtime version (spark_version) of the cluster (confirmed live via `databricks clusters get`)"
  type        = string
  default     = "17.3.x-scala2.13"
}

variable "cluster_autotermination_minutes" {
  description = "Minutes of inactivity before the cluster auto-terminates"
  type        = number
  default     = 10
}

variable "cluster_runtime_engine" {
  description = "Cluster runtime engine: STANDARD or PHOTON"
  type        = string
  default     = "STANDARD"
}

variable "cluster_dev_admin_name" {
  description = "Name of the dev_admin single-node cluster (IT-88) - identical config to the TEST cluster (var.cluster_name), created fresh rather than imported"
  type        = string
  default     = "dev_admin"
}
