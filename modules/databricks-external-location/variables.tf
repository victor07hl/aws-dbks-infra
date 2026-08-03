variable "name" {
  description = "Name of the Unity Catalog external location"
  type        = string
}

variable "s3_url" {
  description = "S3 path this external location covers (s3://bucket/prefix)"
  type        = string
}

variable "create_storage_credential" {
  description = "Whether to create a new databricks_storage_credential for this external location. Default false — reuse an existing storage credential (storage_credential_name) instead, since one self-assuming UC trust role can back every external location in a bucket."
  type        = bool
  default     = false
}

variable "storage_credential_name" {
  description = "Name of the storage credential backing this external location. When create_storage_credential is false (default), this must be the name of an already-registered storage credential to reuse. When true, this is the name given to the new storage credential this module creates."
  type        = string
}

variable "storage_credential_role_arn" {
  description = "ARN of the self-assuming IAM role the new storage credential should assume (e.g. module.iam_storage.role_arn). Required only when create_storage_credential is true; the role's trust policy and bucket permissions must already exist (see modules/iam-storage) — this module does not grant AWS-side S3 access."
  type        = string
  default     = null
}

variable "owner_group" {
  description = "Name of the Databricks principal (typically a group from modules/databricks-identity) to grant privileges on this external location. Optional (default null) — when null, no databricks_grants resource is created."
  type        = string
  default     = null
}

variable "grants" {
  description = "Privileges granted to owner_group on this external location, when owner_group is set."
  type        = list(string)
  default     = ["CREATE_EXTERNAL_TABLE", "CREATE_EXTERNAL_VOLUME"]
}
