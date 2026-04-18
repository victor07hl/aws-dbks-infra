# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform infrastructure project for provisioning Databricks Unity Catalog on AWS.

## Common Commands

```bash
# Initialize Terraform (required before first use or after provider changes)
terraform init

# Preview changes
terraform plan -var-file="terraform.tfvars"

# Apply changes
terraform apply -var-file="terraform.tfvars"

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# Check formatting without writing
terraform fmt -check -recursive
```

## Architecture

- One metastore in us-east-2
- Two workspaces: dev and prod
- Two catalogs: dev (bound to workspace-dev), prod (bound to workspace-prod)
- Two branches: dev (deploys to DEV), main (deploys to PROD)

## Stack
- Terraform for all infrastructure
- AWS provider + Databricks provider
- GitHub Actions for CI/CD


## Rules
- Never hardcode credentials
- Always run terraform plan before apply
- All changes go through feature branch → dev → main
- Follow naming conventions in /docs/naming-conventions.md

`*.tfvars` and `*.tfvars.json` files are gitignored and contain sensitive values — never commit them.

Terraform state files (`*.tfstate`) are also gitignored; remote state (e.g., S3 + DynamoDB locking) is expected for shared environments.
