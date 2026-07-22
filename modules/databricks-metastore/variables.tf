variable "metastore_name" {
  description = "Name of the Unity Catalog metastore"
  type        = string
}

variable "region" {
  description = "AWS region the metastore is created in"
  type        = string
}

variable "delta_sharing_scope" {
  description = "Delta Sharing scope for the metastore (INTERNAL or INTERNAL_AND_EXTERNAL)"
  type        = string
  default     = "INTERNAL"
}

variable "delta_sharing_recipient_token_lifetime_in_seconds" {
  description = "Lifetime of Delta Sharing recipient tokens, in seconds (0 = no expiration)"
  type        = number
  default     = 0
}

variable "force_destroy" {
  description = "Allow the metastore to be destroyed even if it still has catalogs/schemas"
  type        = bool
  default     = false
}
