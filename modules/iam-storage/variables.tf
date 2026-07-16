variable "databricks_account_id" {
  description = "Databricks account ID, used as the sts:ExternalId condition on the self-assuming trust policy"
  type        = string
}

variable "role_name" {
  description = "Name of the self-assuming Unity Catalog storage trust role"
  type        = string
}

variable "role_description" {
  description = "Description attached to the storage trust role, inherited from the manually-provisioned dev role"
  type        = string
  default     = "this is the role the databricks user take to perform actions on s3"
}

variable "bucket_name" {
  description = "Name of the workspace S3 bucket this role is granted read/write access to, sourced from module.s3_workspace.bucket_name"
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the workspace S3 bucket, sourced from module.s3_workspace.bucket_arn"
  type        = string
}

variable "bucket_policy_name" {
  description = "Name of the managed IAM policy granting S3 read/write on the workspace bucket, inherited from the manually-provisioned dev policy"
  type        = string
  default     = "dbks-dev-bucket-policy"
}

variable "file_events_policy_name" {
  description = "Name of the managed IAM policy granting the S3 file-events (SNS/SQS) permissions, inherited from the manually-provisioned dev policy"
  type        = string
  default     = "dbks-dev-policy-s3-file-events"
}
