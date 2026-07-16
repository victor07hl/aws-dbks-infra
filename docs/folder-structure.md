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
│   ├── databricks-workspace/   # Credential / network / storage configs + mws_workspace
│   ├── databricks-catalog/     # Unity Catalog catalog, schemas, workspace binding
│   └── databricks-cluster/     # Reusable cluster compute (all-purpose / job)
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

#### `modules/databricks-workspace/`

Account-level Databricks configurations (credential, network, storage) and the workspace itself.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_mws_credentials`, `databricks_mws_networks`, `databricks_mws_storage_configurations`, `databricks_mws_workspaces` |
| `variables.tf` | `workspace_name`, `region`, credential/network/storage IDs, `databricks_account_id` |
| `outputs.tf` | `workspace_id`, `workspace_url` |

#### `modules/databricks-catalog/`

Unity Catalog catalog, schemas, and workspace binding.

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_catalog`, schemas (`raw`, `bronze`, `silver`, `gold`, `stage`), `databricks_workspace_binding` |
| `variables.tf` | `catalog_name`, `metastore_id`, `workspace_id` |
| `outputs.tf` | `catalog_name`, `catalog_id` |

#### `modules/databricks-cluster/`

Reusable Databricks cluster (all-purpose or job-cluster template).

| File | Purpose |
|------|---------|
| `main.tf` | `databricks_cluster` (or `databricks_job_cluster_template`) |
| `variables.tf` | `cluster_name`, `node_type_id`, `runtime_version`, `autoscale_min`, `autoscale_max` |
| `outputs.tf` | `cluster_id` |

---

### `environments/`

Environment-specific root modules. Each folder is an independent Terraform root with its own remote state. Environments call the shared modules and supply environment-specific variable values.

#### `environments/dev/` and `environments/prod/`

| File | Extension | Purpose |
|------|-----------|---------|
| `main.tf` | `.tf` | Calls the seven `modules/*` modules (network → iam-credential + s3-workspace → iam-storage → databricks-workspace → databricks-catalog, plus databricks-cluster as needed) with env-specific inputs |
| `variables.tf` | `.tf` | Declares all variables used in this environment |
| `outputs.tf` | `.tf` | Exposes key values (workspace URL, catalog name) after apply |
| `providers.tf` | `.tf` | Configures the `aws` and `databricks` providers with region, `default_tags`, and auth settings |
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
| `naming-conventions.md` | `.md` | Naming rules for Terraform resources, modules, variables, and AWS/Databricks objects |

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
- See [naming-conventions.md](naming-conventions.md) for resource naming rules.
