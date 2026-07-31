variable "workspace_id" {
  description = "ID of the Databricks workspace groups are bound to via group_workspace_permissions (module.databricks_workspace.workspace_id)"
  type        = number
}

variable "users" {
  description = "Map of users to create, keyed by an arbitrary short key (e.g. \"alice\") used to reference the user from group_members. Empty by default — creates nothing until populated."
  type = map(object({
    user_name = string
  }))
  default = {}
}

variable "groups" {
  description = "Map of groups to create, keyed by an arbitrary short key used to reference the group from group_members and group_workspace_permissions. Empty by default — creates nothing until populated."
  type = map(object({
    display_name = string
  }))
  default = {}
}

variable "service_principals" {
  description = "Map of service principals to create, keyed by an arbitrary short key used to reference from group_members. Empty by default — creates nothing until populated."
  type = map(object({
    application_id = string
    display_name   = string
  }))
  default = {}
}

variable "group_members" {
  description = <<-EOT
    Group membership, keyed by group key (must match a key in var.groups).
    Each value lists the member keys to add to that group: user keys (from
    var.users) and/or service principal keys (from var.service_principals).

    The "new engineer joins" flow is: add their entry to var.users, then add
    that user key to the relevant group's users list here — no other module
    changes needed.
  EOT
  type = map(object({
    users              = optional(list(string), [])
    service_principals = optional(list(string), [])
  }))
  default = {}
}

variable "group_workspace_permissions" {
  description = "Map of group key (from var.groups) to workspace permission level(s) (e.g. [\"USER\"] or [\"ADMIN\"]) to bind that group into var.workspace_id via account-level permission assignment. Only groups present here get workspace access. Empty by default — binds nothing until populated."
  type        = map(list(string))
  default     = {}
}
