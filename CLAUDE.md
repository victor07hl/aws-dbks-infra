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
- Never hardcode credentials — store them in AWS Secrets Manager (encrypted with a customer-managed KMS key)
- Always run terraform plan before apply
- All changes go through feature branch → dev → main
- Follow naming conventions in `docs/naming-conventions.docx`

`*.tfvars` and `*.tfvars.json` files are gitignored and contain sensitive values — never commit them. Runtime credentials (Databricks PAT, account client secret, etc.) must live in Secrets Manager, not in tfvars.

Terraform state files (`*.tfstate`) are also gitignored; remote state (S3 + DynamoDB locking, KMS-encrypted) is expected for shared environments.

## Documentation
- `docs/naming-conventions.docx` — authoritative naming rules for every resource
- `docs/folder-structure.md` — directory layout and file purpose
- `docs/architecture/aws-infrastructure.drawio` — AWS infrastructure architecture (VPC, IAM, Secrets Manager, KMS, CloudTrail)
- `docs/architecture/databricks-architecture.drawio` — Databricks metastore → workspaces → catalogs → schemas

## Security baseline
- S3 buckets: SSE-KMS (CMK), versioning ON, public access BLOCKED
- Secrets: AWS Secrets Manager with CMK + automatic rotation
- IAM: OIDC federation for GitHub Actions, cross-account roles with `sts:ExternalId` condition for Databricks
- Audit: multi-region CloudTrail with log file validation, shipped to S3 + CloudWatch Logs
