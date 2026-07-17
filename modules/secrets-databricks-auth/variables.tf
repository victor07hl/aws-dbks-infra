variable "secret_name" {
  description = "Name of the Secrets Manager secret holding the Databricks OAuth M2M service-principal credentials"
  type        = string
}

variable "kms_alias" {
  description = "Alias of the CMK used to encrypt the secret, e.g. alias/dbks-infra-dev-kms-sm"
  type        = string
}

variable "secret_description" {
  description = "Description attached to the Secrets Manager secret"
  type        = string
  default     = "Databricks OAuth M2M service-principal client_id/client_secret, populated out-of-band after manual service-principal creation"
}

variable "kms_description" {
  description = "Description attached to the CMK"
  type        = string
  default     = "CMK for the Databricks OAuth M2M service-principal secret"
}
