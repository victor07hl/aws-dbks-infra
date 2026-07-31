# Folder Structure

This document describes the directory layout of the `aws-dbks-infra` Terraform project.

## Overview

```
aws-dbks-infra/
├── modules/
│   ├── network/                # Customer-managed VPC, subnets, RT, IGW, NAT, NACL, SG, DHCP
│   ├── iam-credential/         # Cross-account IAM role for Databricks control plane
│   ├── s3-workspace/           # Per-env workspace bucket (artifacts + UC managed data)
│   ├── iam-storage/            # Self-assuming UC trust role (UCMasterRole + self)
│   ├── databricks-metastore/   # Unity Catalog metastore, no storage_root (account-level, shared)
│   ├── databricks-workspace/   # Credential / network / storage configs + mws_workspace
│   ├── databricks-catalog/     # Unity Catalog catalog, schemas, workspace binding
│   ├── databricks-cluster/     # Reusable cluster compute (all-purpose / job)
│   ├── databricks-cluster-policy/  # Governance contract for compute (ready-for-use, not yet instantiated)
│   └── databricks-identity/    # Users, groups, service principals, workspace assignment (ready-for-use, not yet instantiated)
├── environments/
│   ├── dev/                    # Dev environment root module (branch: dev)
│   └── prod/                   # Prod environment root module (branch: main)
├── .github/
│   └── workflows/              # GitHub Actions CI/CD pipelines
├── docs/                       # Project documentation
├── .gitignore
├── CLAUDE.md                   # Claude Code guidance
└── README.md
```

The module breakdown follows Appendix C of `manual-deployment-findings.md` — one module per part of the manual deployment guide, plus a clusters module on top.

---

## Directory Details

### `modules/`

Reusable Terraform modules. Each module encapsulates a single infrastructure concern and is called by the environment root modules. Modules do not have their own state or provider configuration.

Every module starts with the same three files (`main.tf`, `variables.tf`, `outputs.tf`); modules with significant network or IAM surface area may add `network.tf` or `iam.tf` later.

#### `modules/network/`

Customer-managed VPC: VPC + DHCP option set, public + two private subnets across two AZs, route tables, IGW, NAT Gateway, main NACL with the Databricks-required outbound ports, and the workspace security group.

| File | Purpose |
|------|---------|
| `main.tf` | `aws_vpc`, `aws_vpc_dhcp_options`, subnets, route tables, IGW, NAT Gateway, NACL, security group |
| `variables.tf` | `region`, `vpc_cidr`, `azs`, `private_subnet_cidrs`, `public_subnet_cidrs`, `nat_gateway_count` |
| `outputs.tf` | `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `security_group_id` |

#### `modules/iam-credential/`

Cross-account IAM role for the Databricks control plane (Step 2 of the manual deploy). Trust policy: `arn:aws:iam::414351767826:root` with `sts:ExternalId = <databricks_account_id>`.

| File | Purpose |
|------|---------|
| `main.tf` | `aws_iam_role` + inline EC2 cluster lifecycle policy ("default-restrictions" action set) |
| `variables.tf` | `databricks_account_id`, `role_name` |
| `outputs.tf` | `role_arn` |

#### `modules/s3-workspace/`

Per-environment workspace bucket (`dbks-infra-{env}-s3-ws`). Holds workspace artifacts AND UC managed data under `/unity-catalog/*`. Bucket policy must `Deny s3:*` on `/unity-catalog/*` for `arn:aws:iam::414351767826:root` to block legacy DBFS access.

| File | Purpose |
|------|---------|
| `main.tf` | `aws_s3_bucket`, versioning, public-access block, SSE-KMS, `aws_s3_bucket_policy` |
| `variables.tf` | `bucket_name`, `kms_key_arn`, `databricks_account_id` |
| `outputs.tf` | `bucket_name`, `bucket_arn` |

#### `modules/iam-storage/`

Self-assuming UC trust role (`dbks-{env}-trust-role-ws`). Trust policy lists both `UCMasterRole` and the role's own ARN — see Step 4.3 of the manual guide. Two-pass apply.

| File | Purpose |
|------|---------|
| `main.tf` | `aws_iam_role` (self-assuming trust) + inline storage access policy (S3 R/W on `/unity-catalog/*`, KMS Decrypt, `sts:AssumeRole` on self) |
| `variables.tf` | `databricks_account_id`, `role_name`, `bucket_arn`, `kms_key_arn` |
| `outputs.tf` | `role_arn` |

#### `modules/databricks-metastore/`

Single shared Unity Catalog metastore (`dbks-infra-meta-us2`, account-level, one per region). **No `storage_root`** (project decision) — UC managed data lands in each workspace's own bucket under `/unity-catalog/*` instead. Uses the account-level `provider "databricks"` (alias `account`); the aliased provider must be passed explicitly via the module's `providers = { databricks.account = databricks.account }` block. Adopted into state via a one-time `import` block (since removed — see `git log -- environments/dev/imports.tf`) rather than created fresh, since it was originally provisioned manually per `docs/manual-deployment-findings.md` Part 9.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_metastore` (no `storage_root`) |
| `variables.tf` | `metastore_name`, `region`, `delta_sharing_scope`, `delta_sharing_recipient_token_lifetime_in_seconds`, `force_destroy` |
| `outputs.tf` | `metastore_id` |

#### `modules/databricks-workspace/`

Account-level Databricks configurations (credential, network, storage), the workspace itself, its metastore assignment, and an ADMIN permission assignment granting the OAuth M2M service principal workspace-level access. Uses the account-level `provider "databricks"` (alias `account`), passed explicitly via `providers = { databricks.account = databricks.account }`. Adopted into state via one-time `import` blocks (since removed — see `git log -- environments/dev/imports.tf`) for the four pre-existing pieces (credential/network/storage config, workspace); the metastore assignment and permission assignment were created fresh, since Databricks' metastore-assignment API is an idempotent PUT.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_mws_credentials`, `databricks_mws_networks`, `databricks_mws_storage_configurations`, `databricks_mws_workspaces`, `databricks_metastore_assignment`, `data "databricks_service_principal"`, `databricks_mws_permission_assignment` |
| `variables.tf` | `databricks_account_id`, `credential_name`, `credential_role_arn`, `network_config_name`, `vpc_id`, `subnet_ids`, `security_group_ids`, `storage_config_name`, `bucket_name`, `storage_role_arn`, `workspace_name`, `region`, `pricing_tier`, `metastore_id`, `m2m_service_principal_application_id` |
| `outputs.tf` | `workspace_id`, `workspace_url`, `credentials_id`, `network_id`, `storage_configuration_id` |

#### `modules/databricks-catalog/`

Unity Catalog catalog, one or more schemas, and a workspace binding. Uses the workspace-level `provider "databricks"` (alias `workspace`, `host = var.workspace_host`) — `databricks_catalog`/`databricks_schema`/`databricks_workspace_binding` can only be used with a workspace-level provider.

The single `schema_name`/`schema_owner`-driven `databricks_schema.default` resource is the module's original shape, adopted into state via a one-time `import` block (since removed — see `git log -- environments/dev/imports.tf`) for the pre-existing auto-generated catalog. `additional_schemas` (IT-66) adds a `for_each`-driven `databricks_schema.additional` resource on top of it — a map keyed by schema name (e.g. the remaining medallion layers) — without touching `databricks_schema.default`'s resource address, so existing single-schema catalog instances get zero plan diff.

`storage_root` (catalog-level) and `schema_storage_root`/`additional_schemas.*.storage_root` (schema-level) are all optional (IT-66). Unity Catalog requires any managed storage path to be covered by a registered External Location whenever neither the metastore nor a level above has a `storage_root` of its own — this metastore has none. For a brand-new catalog, prefer leaving the catalog's `storage_root` null (pure logical namespace) and setting `storage_root` per schema instead, each pointing at a subpath under one registered External Location — see `environments/dev/main.tf`'s `databricks_external_location.vicmo` for the pattern.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_catalog`, `databricks_schema.default` (single schema), `databricks_schema.additional` (`for_each` over `additional_schemas`), `databricks_workspace_binding` |
| `variables.tf` | `catalog_name`, `storage_root` (optional), `owner`, `isolation_mode`, `enable_predictive_optimization`, `schema_name`, `schema_owner`, `schema_comment`, `schema_enable_predictive_optimization`, `schema_storage_root` (optional), `additional_schemas`, `workspace_id`, `binding_type` (no `metastore_id` — that's a computed attribute on `databricks_catalog`, not a settable argument) |
| `outputs.tf` | `catalog_name`, `catalog_id`, `schema_full_name`, `additional_schema_full_names` |

`environments/dev` instantiates this module twice: `module.databricks_catalog` manages the pre-existing auto-generated catalog (`dev_<workspace_id>`, only its `default` schema) as-is, left untouched per IT-66's scope decision; `module.databricks_catalog_vicmo` (IT-66) creates the project-scoped `vicmo` catalog per `naming-conventions.docx`'s `{project_name}` pattern, with the full `raw`/`bronze`/`silver`/`gold`/`stage` medallion set from `naming-conventions.docx`'s Schemas table (`raw` via the single-schema slot, the rest via `additional_schemas`), each schema's storage under `environments/dev/main.tf`'s `databricks_external_location.vicmo` (backed by `databricks_storage_credential.vicmo`, reusing the existing self-assuming UC trust role from `modules/iam-storage` rather than provisioning new IAM). These two new top-level resources are a minimal, inline stand-in for the not-yet-built `modules/databricks-external-location` (tracked separately as IT-74) — expect them to move into that module once it exists, rather than staying as bespoke resources in the environment root.

#### `modules/databricks-cluster/`

Databricks cluster, single-node or multi-worker depending on `var.is_single_node` (default `true`). Uses the workspace-level `provider "databricks"` (alias `workspace`), same as `modules/databricks-catalog`. The single-node shape was adopted into state via a one-time `import` block (since removed — see `git log -- environments/dev/imports.tf`), since the live `TEST` cluster predates this module: it was created manually via Compute -> Create cluster as the smoke-test cluster in `docs/manual-deployment-findings.md`. `dev_admin` (IT-88) is a second, config-identical single-node instance created fresh (not imported).

Two `databricks_cluster` resources, gated by `count` on `var.is_single_node`, rather than one resource with conditional arguments — `lifecycle.ignore_changes` must be a static list (Terraform constraint), so the single-node-only ignore-rule below has to live on a resource that only single-node clusters use (IT-71):

- `single_node` (`count = var.is_single_node ? 1 : 0`) — simplified single-node cluster (`is_single_node = true`, `kind = "CLASSIC_PREVIEW"`). Databricks auto-manages `custom_tags`, `spark_conf`, and `num_workers` rather than the module setting them explicitly; those two fields aren't marked `Computed` in the provider schema, so they're covered by `lifecycle { ignore_changes = [custom_tags, spark_conf] }` to stop Terraform from nulling them out every plan.
- `multi_node` (`count = var.is_single_node ? 0 : 1`) — `autoscale { min_workers, max_workers }`, caller-controlled `data_security_mode` (`SINGLE_USER` or `USER_ISOLATION` for UC).

Changing a live instance's `is_single_node` value would move it between these two resources — that's a destroy+recreate, not an in-place update; don't do it without a deliberate migration plan.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_cluster.single_node` (single-node), `databricks_cluster.multi_node` (autoscaling) |
| `variables.tf` | `cluster_name`, `node_type_id`, `spark_version`, `autotermination_minutes`, `runtime_engine`, `policy_id`, `is_single_node`, `data_security_mode`, `autoscale_min`, `autoscale_max` |
| `outputs.tf` | `cluster_id`, `cluster_name` (via `one(concat(...))` across whichever of the two resources exists) |

#### `modules/databricks-cluster-policy/`

Governance contract for compute (IT-72): a `databricks_cluster_policy` constraining node types, autoscale range, autotermination, DBR version, etc. via a JSON `definition`. Uses the workspace-level `provider "databricks"` (alias `workspace`), same as `modules/databricks-cluster`. Its `policy_id` output is meant to feed `modules/databricks-cluster`'s `policy_id` input.

**Ready-for-use only** — authored and `fmt`/`validate`-clean, but not instantiated in any environment root yet (no live policy exists). See the commented example module call at the top of `main.tf`.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_cluster_policy.this` |
| `variables.tf` | `policy_name`, `definition`, `max_clusters_per_user` (optional) |
| `outputs.tf` | `policy_id` |

#### `modules/databricks-identity/`

Identity module (IT-73) for users, groups, service principals, and workspace binding — designed so the "new engineer joins" flow is just adding one entry to `group_members`. Uses the account-level `provider "databricks"` (alias `account`) throughout, since every resource here (`databricks_user`, `databricks_group`, `databricks_service_principal`, `databricks_group_member`, `databricks_mws_permission_assignment`) is account-level; no workspace-level provider is needed.

All four collection inputs (`users`, `groups`, `service_principals`, `group_members`) and `group_workspace_permissions` default empty, so the module creates nothing until populated. Membership is expressed as maps keyed by short reference keys (not by user_name/display_name directly) so `group_members` can cross-reference `users`/`service_principals` entries; `group_workspace_permissions` reuses the same `databricks_mws_permission_assignment` resource and account-level pattern already established in `modules/databricks-workspace` for the M2M service principal's ADMIN assignment.

**Ready-for-use only** — authored and `fmt`/`validate`-clean, but not instantiated in any environment root yet (no live users/groups exist). See the commented example module call (a "data-engineers" group with one member) at the top of `main.tf`.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_user.this`, `databricks_group.this`, `databricks_service_principal.this` (all `for_each`), `databricks_group_member.user`/`.service_principal` (flattened membership), `databricks_mws_permission_assignment.group` |
| `variables.tf` | `workspace_id`, `users`, `groups`, `service_principals`, `group_members`, `group_workspace_permissions` |
| `outputs.tf` | `user_ids`, `group_ids`, `service_principal_ids` (all maps keyed by the input reference key) |

---

### `environments/`

Environment-specific root modules. Each folder is an independent Terraform root with its own remote state. Environments call the shared modules and supply environment-specific variable values.

#### `environments/dev/` and `environments/prod/`

| File | Extension | Purpose |
|------|-----------|---------|
| `main.tf` | `.tf` | Calls the `modules/*` modules (network → iam-credential + s3-workspace → iam-storage → secrets-databricks-auth → databricks-metastore → databricks-workspace → databricks-catalog → databricks-cluster) with env-specific inputs. All eight modules are wired in `environments/dev/main.tf` (IT-70 wired the last one, databricks-cluster) |
| `variables.tf` | `.tf` | Declares all variables used in this environment |
| `outputs.tf` | `.tf` | *(not yet created)* Intended to expose key values (workspace URL, catalog name) after apply |
| `providers.tf` | `.tf` | Configures the `aws` provider and two aliased `databricks` providers: `account` (`accounts.cloud.databricks.com`, for metastore/workspace-level account resources) and `workspace` (`var.workspace_host`, for catalog/schema/binding resources) — both authenticate with the same OAuth M2M service-principal credentials from Secrets Manager |
| `versions.tf` | `.tf` | `required_version >= 1.10` and pinned `required_providers` (aws ~> 5.0, databricks ~> 1.39) |
| `backend.tf` | `.tf` | Remote state in S3 (`dbks-infra-s3-tf-state`) with native S3 locking via `use_lockfile = true` — no DynamoDB |
| `terraform.tfvars` | `.tfvars` | *(gitignored)* Actual sensitive values: tokens, account IDs, bucket names |
| `terraform.tfvars.example` | `.tfvars` | Safe template showing required variables without real values — committed to git |

---

### `.github/workflows/`

GitHub Actions CI/CD pipeline definitions. All files use YAML format.

| File | Extension | Trigger | Purpose |
|------|-----------|---------|---------|
| `plan-dev.yml` | `.yml` | PR opened targeting `dev` | Runs `terraform plan` against the dev environment |
| `apply-dev.yml` | `.yml` | Push to `dev` branch | Runs `terraform apply` against the dev environment |
| `plan-prod.yml` | `.yml` | PR opened targeting `main` | Runs `terraform plan` against the prod environment |
| `apply-prod.yml` | `.yml` | Merge to `main` branch | Runs `terraform apply` against the prod environment |

Each workflow file contains:
- Checkout step
- Terraform setup (`hashicorp/setup-terraform` action)
- AWS credentials configuration via GitHub Secrets
- `terraform init`, `validate`, `plan` / `apply` steps

---

### `docs/`

Project documentation in Markdown format.

| File | Extension | Purpose |
|------|-----------|---------|
| `folder-structure.md` | `.md` | This file — directory layout and file conventions |
| `naming-conventions.docx` | `.docx` | Naming rules for Terraform resources, modules, variables, and AWS/Databricks objects |

---

## File Extension Reference

| Extension | Used for |
|-----------|---------|
| `.tf` | Terraform configuration files (resources, variables, outputs, providers, backends) |
| `.tfvars` | Terraform variable value files — gitignored for real values, committed for `.example` templates |
| `.yml` | GitHub Actions workflow definitions |
| `.md` | Documentation files |
| `.gitkeep` | Empty placeholder to track empty directories in git |
| `.json` | Terraform-generated lock files (`terraform.lock.hcl`) or policy documents |

---

## Conventions

- Never hardcode credentials — use `terraform.tfvars` (gitignored) or environment variables.
- Always run `terraform plan` before `terraform apply`.
- All changes flow through: `feature branch → dev → main`.
- State files (`*.tfstate`) are gitignored; remote state is managed via S3 with native locking (`use_lockfile = true`, Terraform ≥ 1.10) — no DynamoDB.
- Every root-module variable in `environments/{dev,prod}` needs a `default`, since no CI workflow passes `-var-file`/`-var` (see `plan-dev.yml`/`apply-dev.yml`/etc.) — `terraform.tfvars` is local-only and gitignored.
- See [naming-conventions.docx](naming-conventions.docx) for resource naming rules.
