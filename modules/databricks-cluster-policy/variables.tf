variable "policy_name" {
  description = "Name of the Databricks cluster policy"
  type        = string
}

variable "definition" {
  description = "Cluster policy definition as a JSON string (constrains node types, autoscale range, autotermination, DBR version, etc. — see Databricks cluster policy docs for the schema)"
  type        = string
}

variable "max_clusters_per_user" {
  description = "Optional cap on the number of clusters a single user can create under this policy"
  type        = number
  default     = null
}
