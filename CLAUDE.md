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
- Two workspaces: dev and prod — Databricks workspace *names* follow the `DEV`/`PROD` convention in `docs/naming-conventions.docx` (not the `dbks-infra-{env}-*` pattern used for AWS/other Databricks object types); live dev workspace is `DEV`
- Two catalogs: dev (bound to workspace-dev), prod (bound to workspace-prod) — **dev's catalog is currently Unity Catalog's auto-generated default** (`dev_<workspace_id>`), not a project-named catalog, and only has its `default` schema (no `raw/bronze/silver/gold/stage` medallion set yet). See "Known drift" below (IT-66)
- Two branches: dev (deploys to DEV), main (deploys to PROD)

### Storage topology
- **`dbks-infra-s3-tf-state`** — shared Terraform remote state (default SSE-S3, no KMS — project decision)
- **`dbks-infra-{env}-s3-ws`** — one bucket per environment that holds **both** workspace artifacts **and** UC managed data under `/unity-catalog/*`. Bucket policy must `Deny s3:*` on `/unity-catalog/*` for the Databricks root principal to block legacy DBFS access.
- **No separate metastore bucket** — UC managed data lives in the workspace bucket because the metastore has no `storage_root`.

### Auth
- Databricks OAuth M2M service-principal credentials live in `dbks-infra-{env}-sm-databricks-m2m` (Secrets Manager, per-env CMK, `modules/secrets-databricks-auth`) — Terraform creates the container with a placeholder version (`lifecycle { ignore_changes = [secret_string] }`), the real value is populated out-of-band after manually creating the service principal (`docs/terraform-setup-aws.md` Part 9)
- Account-level `provider "databricks"` (`alias = "account"`, host `https://accounts.cloud.databricks.com`) reads those credentials via `data "aws_secretsmanager_secret_version"` — never hardcoded
- Workspace-level `provider "databricks"` (`alias = "workspace"`, `host = var.workspace_host` — a plain variable defaulted to the known live URL, not derived from a computed workspace attribute) uses the same credentials; required because `databricks_catalog`/`databricks_schema`/`databricks_workspace_binding` only work with a workspace-level provider
- The same service principal is granted workspace `ADMIN` via `databricks_mws_permission_assignment` in `modules/databricks-workspace`, so it can authenticate at the workspace level (not just the account level) to manage catalog/schema objects

## Stack
- Terraform for all infrastructure
- AWS provider + Databricks provider
- GitHub Actions for CI/CD


## Rules
- Never hardcode credentials — store them in AWS Secrets Manager (encrypted with a customer-managed KMS key)
- Always run terraform plan before apply
- All changes go through a ticket-named feature branch → dev → main. Feature branches are named `IT_<n>_branch` (e.g. `IT_21_branch`); every promotion is a PR requiring ≥1 approving review. See "Branch and Deployment Strategy" in `docs/terraform-setup-aws.md`. Note: these PR rules are a team convention, not GitHub-enforced (private repo on the Free plan)
- Follow naming conventions in `docs/naming-conventions.docx`
- Every root-module variable in `environments/{dev,prod}` must have a `default`, or the relevant GitHub Actions workflow must be updated to supply it. None of the four workflows (`plan-dev.yml`, `apply-dev.yml`, `plan-prod.yml`, `apply-prod.yml`) pass `-var-file`/`-var`/`TF_VAR_*` — `terraform.tfvars` is gitignored and never present on CI runners. A required variable with no default hangs `plan`/`apply` in CI (Terraform waits on interactive input with no TTY) until GitHub kills the job hours later, and can leave stale S3 native-locking lock objects behind (`terraform force-unlock <id>` to clear)
- When moving an already-applied resource into (or out of) a module — e.g. modularizing the remaining flat resources in `generated.tf` (IAM, S3) the same way `modules/network` was done — always reconcile with `terraform state mv <old_address> <new_address>` for each resource before merging. Editing the `.tf` files alone doesn't move state, so `plan` will otherwise show a full destroy+recreate instead of a no-op

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

## Known drift / open follow-ups
- **IT-66** — dev's live catalog is Unity Catalog's auto-generated default (`dev_<workspace_id>`), not a project-named catalog per `docs/naming-conventions.docx`; the `raw/bronze/silver/gold/stage` schemas from `docs/folder-structure.md` were never created.
- **S3 workspace bucket** (`dbks-infra-dev-s3-ws`) has versioning disabled and SSE-S3 (not SSE-KMS) in the already-applied live bucket — contradicts the security baseline above; preserved as-is in Terraform (state-move only, not a config fix) pending a deliberate remediation.
- **No NACL** is currently defined in `modules/network` (relies on the AWS default allow-all NACL) despite being described in `docs/architecture/network-topology.md`.
- **NAT Gateway is the dominant AWS cost driver** for dev (~$30/month, running 24/7) — `docs/manual-deployment-findings.md` Appendix C recommends VPC endpoints (S3/DynamoDB gateway; STS/Kinesis/Secrets Manager/KMS interface) to cut this and keep secret retrieval off the public path; not yet implemented.
- A leftover manual test EC2 instance (`dbks-infra-dev-vm-test`, from the connectivity check in `docs/manual-deployment-findings.md` Part 1) was never terminated — currently **stopped** (negligible cost), unmanaged by Terraform, candidate for cleanup.
