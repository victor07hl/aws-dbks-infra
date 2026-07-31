variable "catalog_name" {
  description = "Name of the Unity Catalog catalog"
  type        = string
}

variable "storage_root" {
  description = "S3 path backing the catalog's managed data (module.s3_workspace.bucket_name path — no separate metastore bucket)"
  type        = string
}

variable "owner" {
  description = "Owner principal of the catalog (Databricks auto-assigns \"_workspace_admins_<catalog_name>\" for a workspace's default catalog)"
  type        = string
}

variable "isolation_mode" {
  description = "Catalog isolation mode: OPEN or ISOLATED"
  type        = string
  default     = "ISOLATED"
}

variable "enable_predictive_optimization" {
  description = "Predictive optimization setting: ENABLE, DISABLE, or INHERIT"
  type        = string
  default     = "INHERIT"
}

variable "schema_name" {
  description = "Name of the schema being managed within the catalog"
  type        = string
  default     = "default"
}

variable "schema_owner" {
  description = "Owner principal of the schema"
  type        = string
}

variable "schema_comment" {
  description = "Comment on the schema"
  type        = string
  default     = "Default schema (auto-created)"
}

variable "schema_enable_predictive_optimization" {
  description = "Predictive optimization setting for the schema: ENABLE, DISABLE, or INHERIT"
  type        = string
  default     = "INHERIT"
}

variable "workspace_id" {
  description = "ID of the Databricks workspace the catalog is exclusively bound to (module.databricks_workspace.workspace_id)"
  type        = number
}

variable "binding_type" {
  description = "Workspace binding mode: BINDING_TYPE_READ_WRITE or BINDING_TYPE_READ_ONLY"
  type        = string
  default     = "BINDING_TYPE_READ_WRITE"
}

variable "additional_schemas" {
  description = <<-EOT
    Extra schemas to create in the catalog, keyed by schema name (e.g. the
    remaining medallion layers bronze/silver/gold/stage), on top of the
    single schema_name/schema_owner slot above. Empty by default, so
    existing catalog instances that only need one schema are unaffected
    (IT-66).
  EOT
  type = map(object({
    owner                          = string
    comment                        = optional(string, "")
    enable_predictive_optimization = optional(string, "INHERIT")
  }))
  default = {}
}
