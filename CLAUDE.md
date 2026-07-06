# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform infrastructure project for provisioning Databricks Unity Catalog on AWS.

## Common Commands

All Terraform commands must be run from within an environment directory (`environments/dev` or `environments/prod`).

```bash
# Initialize Terraform (required before first use or after provider changes)
terraform -chdir=environments/dev init

# Preview changes
terraform -chdir=environments/dev plan -var-file="terraform.tfvars"

# Apply changes
terraform -chdir=environments/dev apply -var-file="terraform.tfvars"

# Destroy infrastructure
terraform -chdir=environments/dev destroy -var-file="terraform.tfvars"

# Validate configuration
terraform -chdir=environments/dev validate

# Format code (run from repo root)
terraform fmt -recursive

# Check formatting without writing (run from repo root)
terraform fmt -check -recursive
```

## Architecture

- One metastore in us-east-2 (`dbks-infra-meta-us2`) — **no `storage_root`** configured
- Two workspaces: dev and prod
- Two catalogs: dev (bound to workspace-dev), prod (bound to workspace-prod)
- Two branches: dev (deploys to DEV), main (deploys to PROD)

### Storage topology
- **`dbks-infra-s3-tf-state`** — shared Terraform remote state (default SSE-S3, no KMS — project decision)
- **`dbks-infra-{env}-s3-ws`** — one bucket per environment that holds **both** workspace artifacts **and** UC managed data under `/unity-catalog/*`. Bucket policy must `Deny s3:*` on `/unity-catalog/*` for the Databricks root principal to block legacy DBFS access.
- **No separate metastore bucket** — UC managed data lives in the workspace bucket because the metastore has no `storage_root`.

## Stack
- Terraform for all infrastructure
- AWS provider + Databricks provider
- GitHub Actions for CI/CD


## Rules
- Never hardcode credentials — store them in AWS Secrets Manager (encrypted with a customer-managed KMS key)
- Always run terraform plan before apply
- All changes go through a ticket-named feature branch → dev → main. Feature branches are named `IT_<n>_branch` (e.g. `IT_21_branch`); every promotion is a PR requiring ≥1 approving review. See "Branch and Deployment Strategy" in `docs/terraform-setup-aws.md`. Note: these PR rules are a team convention, not GitHub-enforced (private repo on the Free plan)
- Follow naming conventions in `docs/naming-conventions.docx`

`*.tfvars` and `*.tfvars.json` files are gitignored and contain sensitive values — never commit them. Runtime credentials (Databricks PAT, account client secret, etc.) must live in Secrets Manager, not in tfvars.

Terraform state files (`*.tfstate`) are also gitignored; remote state uses S3 with native locking (`use_lockfile = true`, Terraform ≥ 1.10) and SSE-S3 encryption — no DynamoDB, no KMS per project decision (see `docs/terraform-setup-aws.md`).

## Documentation
- `docs/naming-conventions.docx` — authoritative naming rules for every resource
- `docs/folder-structure.md` — directory layout and file purpose
- `docs/manual-deployment-findings.md` — full click-by-click manual deploy guide (Parts 1–12); Appendix C has the canonical Terraform module breakdown to follow when implementing
- `docs/terraform-setup-aws.md` — Terraform-on-AWS bootstrap runbook: state bucket (S3 + native locking, **no DynamoDB**, Terraform 1.10+), local SSO + assume-role, GitHub Actions OIDC trust
- `docs/architecture/network-topology.md` — dev VPC, subnet, route-table, NACL, NAT, IGW spec
- `docs/architecture/aws-infrastructure.drawio` — multi-page diagram: networking, workspace structure, components infra, storage, IAM, CI/CD pipeline

## Security baseline
- S3 buckets: SSE-KMS (per-env CMK), versioning ON, public access BLOCKED — **except** `dbks-infra-s3-tf-state`, which uses default SSE-S3 (no KMS) per project decision
- Secrets: AWS Secrets Manager with CMK + automatic rotation
- IAM: OIDC federation for GitHub Actions, cross-account roles with `sts:ExternalId` condition for Databricks. The UC storage trust role (`dbks-{env}-trust-role-ws`) must be **self-assuming** — its trust policy lists both `UCMasterRole` and the role's own ARN
- Audit: multi-region CloudTrail with log file validation, shipped to S3 + CloudWatch Logs
