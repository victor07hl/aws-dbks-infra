terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.account]
    }
  }
}

# Ready-for-use (IT-73): authored + validated, not instantiated in any
# environment root yet. All inputs default empty, so this module creates
# nothing until populated. Example usage — a "data-engineers" group with one
# member, granted USER access to a workspace:
#
# module "databricks_identity" {
#   source = "../../modules/databricks-identity"
#   providers = {
#     databricks.account = databricks.account
#   }
#
#   workspace_id = module.databricks_workspace.workspace_id
#
#   users = {
#     alice = { user_name = "alice@example.com" }
#   }
#   groups = {
#     data_engineers = { display_name = "data-engineers" }
#   }
#   group_members = {
#     data_engineers = { users = ["alice"] }
#   }
#   group_workspace_permissions = {
#     data_engineers = ["USER"]
#   }
# }
#
# Onboarding a new engineer onto an existing group is then just adding their
# key to `users` and to that group's `users` list in `group_members`.

resource "databricks_user" "this" {
  for_each = var.users
  provider = databricks.account

  user_name = each.value.user_name
}

resource "databricks_group" "this" {
  for_each = var.groups
  provider = databricks.account

  display_name = each.value.display_name
}

resource "databricks_service_principal" "this" {
  for_each = var.service_principals
  provider = databricks.account

  application_id = each.value.application_id
  display_name   = each.value.display_name
}

locals {
  # Flatten group_members into per-membership entries so each membership can
  # be its own for_each key (databricks_group_member has no native for_each
  # over a nested list of members).
  group_user_memberships = { for m in flatten([
    for group_key, membership in var.group_members : [
      for user_key in membership.users : {
        key       = "${group_key}.${user_key}"
        group_key = group_key
        user_key  = user_key
      }
    ]
  ]) : m.key => m }

  group_sp_memberships = { for m in flatten([
    for group_key, membership in var.group_members : [
      for sp_key in membership.service_principals : {
        key       = "${group_key}.${sp_key}"
        group_key = group_key
        sp_key    = sp_key
      }
    ]
  ]) : m.key => m }
}

resource "databricks_group_member" "user" {
  for_each = local.group_user_memberships
  provider = databricks.account

  group_id  = databricks_group.this[each.value.group_key].id
  member_id = databricks_user.this[each.value.user_key].id
}

resource "databricks_group_member" "service_principal" {
  for_each = local.group_sp_memberships
  provider = databricks.account

  group_id  = databricks_group.this[each.value.group_key].id
  member_id = databricks_service_principal.this[each.value.sp_key].id
}

# Workspace binding: account-level permission assignment, same resource and
# provider used for the M2M service principal's ADMIN assignment in
# modules/databricks-workspace.
resource "databricks_mws_permission_assignment" "group" {
  for_each = var.group_workspace_permissions
  provider = databricks.account

  workspace_id = var.workspace_id
  principal_id = databricks_group.this[each.key].id
  permissions  = each.value
}
