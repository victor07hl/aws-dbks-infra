variable "catalog_name" {
  description = "Name of the Unity Catalog catalog"
  type        = string
}

variable "storage_root" {
  description = "S3 path backing the catalog's own managed data. Optional (default null) — Unity Catalog requires this be covered by a registered External Location when neither the metastore nor this catalog has a storage_root, so a fresh catalog with no External Location of its own should leave this null and instead set storage_root per-schema (see schema_storage_root / additional_schemas.*.storage_root) (IT-66)."
  type        = string
  default     = null
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

variable "schema_storage_root" {
  description = "S3 path backing the default schema's managed data. Optional (default null) — when set, must be covered by a registered External Location (IT-66); when null, the schema inherits the catalog's storage_root instead."
  type        = string
  default     = null
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
    (IT-66). Each entry's storage_root is optional (default null) — when
    set, must be covered by a registered External Location.
  EOT
  type = map(object({
    owner                          = string
    comment                        = optional(string, "")
    enable_predictive_optimization = optional(string, "INHERIT")
    storage_root                   = optional(string)
  }))
  default = {}
}
