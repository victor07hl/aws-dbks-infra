variable "databricks_account_id" {
  description = "Databricks account ID"
  type        = string
}

variable "credential_name" {
  description = "Name of the Databricks credential configuration (cross-account IAM role for the control plane)"
  type        = string
}

variable "credential_role_arn" {
  description = "ARN of the cross-account credential IAM role (module.iam_credential.role_arn)"
  type        = string
}

variable "network_config_name" {
  description = "Name of the Databricks network configuration"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the workspace is deployed into"
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the private subnets used by the workspace (public subnet excluded)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "IDs of the security group(s) used by the workspace"
  type        = list(string)
}

variable "storage_config_name" {
  description = "Name of the Databricks storage configuration"
  type        = string
}

variable "bucket_name" {
  description = "Name of the workspace root S3 bucket (module.s3_workspace.bucket_name — no separate root bucket)"
  type        = string
}

variable "storage_role_arn" {
  description = "ARN of the self-assuming Unity Catalog storage trust role (module.iam_storage.role_arn), shared between workspace root storage and the default catalog since there's no separate metastore bucket"
  type        = string
}

variable "workspace_name" {
  description = "Name of the Databricks workspace"
  type        = string
}

variable "region" {
  description = "AWS region the workspace is deployed into"
  type        = string
}

variable "pricing_tier" {
  description = "Databricks pricing tier (PREMIUM required for Unity Catalog)"
  type        = string
  default     = "PREMIUM"
}

variable "metastore_id" {
  description = "ID of the Unity Catalog metastore to assign to this workspace (module.databricks_metastore.metastore_id)"
  type        = string
}

variable "m2m_service_principal_application_id" {
  description = "Application (client) ID of the Databricks OAuth M2M service principal to grant workspace ADMIN, so it can authenticate at the workspace level"
  type        = string
}
