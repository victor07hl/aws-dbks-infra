variable "cluster_name" {
  description = "Name of the Databricks cluster"
  type        = string
}

variable "node_type_id" {
  description = "AWS instance type for the cluster nodes (single-node: combined driver + executor; multi-worker: driver and worker node type)"
  type        = string
}

variable "spark_version" {
  description = "Databricks Runtime version (spark_version), e.g. \"17.3.x-scala2.13\""
  type        = string
}

variable "autotermination_minutes" {
  description = "Minutes of inactivity before the cluster auto-terminates"
  type        = number
  default     = 20
}

variable "runtime_engine" {
  description = "Cluster runtime engine: STANDARD or PHOTON"
  type        = string
  default     = "STANDARD"
}

variable "policy_id" {
  description = "Optional cluster policy ID to attach"
  type        = string
  default     = null
}

variable "is_single_node" {
  description = "true for a simplified single-node cluster (is_single_node/kind = CLASSIC_PREVIEW); false for a multi-worker autoscaling cluster. Determines which of the two databricks_cluster resources in this module gets created (IT-71)."
  type        = bool
  default     = true
}

variable "data_security_mode" {
  description = "Unity Catalog access mode for multi-worker clusters: SINGLE_USER or USER_ISOLATION. Not used when is_single_node = true (single-node clusters default to DATA_SECURITY_MODE_AUTO, platform-managed)."
  type        = string
  default     = "USER_ISOLATION"
}

variable "autoscale_min" {
  description = "Minimum worker count for a multi-worker cluster's autoscale range. Not used when is_single_node = true."
  type        = number
  default     = 1
}

variable "autoscale_max" {
  description = "Maximum worker count for a multi-worker cluster's autoscale range. Not used when is_single_node = true."
  type        = number
  default     = 2
}
