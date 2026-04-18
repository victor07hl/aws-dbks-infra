# Folder Structure

This document describes the directory layout of the `aws-dbks-infra` Terraform project.

## Overview

```
aws-dbks-infra/
├── modules/
│   ├── metastore/        # Unity Catalog metastore (us-east-2)
│   ├── workspace/        # Databricks workspace (dev & prod)
│   └── catalog/          # Unity Catalog catalogs bound to workspaces
├── environments/
│   ├── dev/              # Dev environment root module (branch: dev)
│   └── prod/             # Prod environment root module (branch: main)
├── .github/
│   └── workflows/        # GitHub Actions CI/CD pipelines
├── docs/                 # Project documentation
├── .gitignore
├── CLAUDE.md             # Claude Code guidance
└── README.md
```

---

## Directory Details

### `modules/`

Reusable Terraform modules. Each module encapsulates a single infrastructure concern and is called by the environment root modules. Modules do not have their own state or provider configuration.

#### `modules/metastore/`

Provisions the single Unity Catalog metastore in `us-east-2`, shared across all workspaces.

| File | Extension | Purpose |
|------|-----------|---------|
| `main.tf` | `.tf` | Core resource definitions: `databricks_metastore`, S3 bucket for metastore storage |
| `variables.tf` | `.tf` | Input variable declarations (region, bucket name, owner, etc.) |
| `outputs.tf` | `.tf` | Exported values consumed by other modules (metastore ID, bucket ARN) |
| `iam.tf` | `.tf` | IAM roles and policies required by the metastore |

#### `modules/workspace/`

Provisions a Databricks workspace on AWS. Used once per environment (dev and prod).

| File | Extension | Purpose |
|------|-----------|---------|
| `main.tf` | `.tf` | Core resource definitions: `databricks_mws_workspaces`, VPC, subnets, security groups |
| `variables.tf` | `.tf` | Input variable declarations (workspace name, region, network config, credentials) |
| `outputs.tf` | `.tf` | Exported values: workspace URL, workspace ID |
| `network.tf` | `.tf` | VPC, subnets, NAT gateway, and security group resources |
| `iam.tf` | `.tf` | Cross-account IAM role for Databricks control plane access |

#### `modules/catalog/`

Provisions a Unity Catalog catalog and binds it to a specific workspace.

| File | Extension | Purpose |
|------|-----------|---------|
| `main.tf` | `.tf` | Core resource definitions: `databricks_catalog`, `databricks_catalog_workspace_binding` |
| `variables.tf` | `.tf` | Input variable declarations (catalog name, metastore ID, workspace ID) |
| `outputs.tf` | `.tf` | Exported values: catalog name, catalog ID |

---

### `environments/`

Environment-specific root modules. Each folder is an independent Terraform root with its own remote state. Environments call the shared modules and supply environment-specific variable values.

#### `environments/dev/` and `environments/prod/`

| File | Extension | Purpose |
|------|-----------|---------|
| `main.tf` | `.tf` | Calls `modules/metastore`, `modules/workspace`, and `modules/catalog` with env-specific inputs |
| `variables.tf` | `.tf` | Declares all variables used in this environment |
| `outputs.tf` | `.tf` | Exposes key values (workspace URL, catalog name) after apply |
| `providers.tf` | `.tf` | Configures the `aws` and `databricks` providers with region and auth settings |
| `backend.tf` | `.tf` | Remote state configuration pointing to S3 bucket + DynamoDB lock table |
| `terraform.tfvars` | `.tfvars` | *(gitignored)* Actual sensitive values: tokens, account IDs, bucket names |
| `terraform.tfvars.example` | `.tfvars` | Safe template showing required variables without real values — committed to git |

---

### `.github/workflows/`

GitHub Actions CI/CD pipeline definitions. All files use YAML format.

| File | Extension | Trigger | Purpose |
|------|-----------|---------|---------|
| `plan-dev.yml` | `.yml` | Push to `dev` branch | Runs `terraform plan` against the dev environment |
| `apply-dev.yml` | `.yml` | Merge to `dev` branch | Runs `terraform apply` against the dev environment |
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
- State files (`*.tfstate`) are gitignored; remote state is managed via S3 + DynamoDB.
- See [naming-conventions.md](naming-conventions.md) for resource naming rules.
