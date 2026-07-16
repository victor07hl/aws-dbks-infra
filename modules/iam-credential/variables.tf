variable "databricks_account_id" {
  description = "Databricks account ID, used as the sts:ExternalId condition on the cross-account trust policy"
  type        = string
}

variable "role_name" {
  description = "Name of the cross-account IAM role assumed by the Databricks control plane"
  type        = string
}

variable "policy_name" {
  description = "Name of the inline EC2 cluster-lifecycle policy attached to the credential role, inherited from the manually-provisioned dev role"
  type        = string
  default     = "dbks-dev-ws-policy"
}

variable "role_description" {
  description = "Description attached to the credential IAM role, inherited from the manually-provisioned dev role"
  type        = string
  default     = "this is the role used for the dbks dev "
}
