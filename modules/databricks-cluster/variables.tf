variable "cluster_name" {
  description = "Name of the Databricks cluster"
  type        = string
}

variable "node_type_id" {
  description = "AWS instance type for the single node (combined driver + executor)"
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
