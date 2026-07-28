# aws-dbks-infra

Terraform infrastructure for Databricks Unity Catalog on AWS. Provisions two isolated environments (dev / prod) with separate VPCs, S3 workspace buckets, IAM roles, and Databricks workspace + catalog resources.

## Architecture

- **Region:** `us-east-2`
- **Metastore:** one shared account-level metastore (`dbks-infra-meta-us2`) with no `storage_root`
- **Environments:** dev and prod — each is an independent Terraform root with its own remote state
- **Workspaces:** one per environment, each bound to its own UC catalog. Databricks workspace *names* follow the `DEV`/`PROD` convention (live dev workspace is `DEV`, not `dbks-infra-dev-ws`)
- **Catalogs:** dev and prod, intended to have `raw / bronze / silver / gold / stage` schemas — **dev currently runs on Unity Catalog's auto-generated default catalog** (`dev_<workspace_id>`) with only its `default` schema, since the project-named catalog was never actually created (tracked in Jira IT-66)

### Module breakdown

| Module | Purpose |
|---|---|
| `modules/network` | Customer-managed VPC, subnets, IGW, NAT, security group (no NACL defined yet — see Known drift in `CLAUDE.md`) |
| `modules/iam-credential` | Cross-account IAM role for the Databricks control plane |
| `modules/s3-workspace` | Per-env workspace bucket (artifacts + UC managed data under `/unity-catalog/*`) |
| `modules/iam-storage` | Self-assuming UC trust role (`UCMasterRole` + self in trust policy) |
| `modules/secrets-databricks-auth` | Per-env CMK + Secrets Manager container for Databricks OAuth M2M service-principal credentials, read by the account-level `provider "databricks"` block |
| `modules/databricks-metastore` | Unity Catalog metastore (no `storage_root`) |
| `modules/databricks-workspace` | Databricks credential / network / storage configs, `mws_workspace`, metastore assignment, and an ADMIN permission assignment for the OAuth M2M service principal |
| `modules/databricks-catalog` | Unity Catalog catalog, a schema, and a workspace binding (uses the workspace-level `provider "databricks"`) |
| `modules/databricks-cluster` | Reusable cluster compute (all-purpose / job) — **not yet implemented or wired in** |

### Remote state

State is stored in `dbks-infra-s3-tf-state` with native S3 locking (`use_lockfile = true`, Terraform ≥ 1.10) and SSE-S3 encryption. No DynamoDB, no KMS — project decision.

| Key | Environment |
|---|---|
| `envs/dev/terraform.tfstate` | dev |
| `envs/prod/terraform.tfstate` | prod |

## Prerequisites

- Terraform `>= 1.10`
- AWS CLI v2 with SSO configured (see `docs/terraform-setup-aws.md`)
- Access to the `dbks-infra-iam-role-tf-local` IAM role for local plan/apply

## Getting started

1. Bootstrap AWS resources (state bucket, IAM roles, OIDC provider) — follow `docs/terraform-setup-aws.md`
2. Copy and fill in variable values:
   ```bash
   cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
   # edit terraform.tfvars with real values
   ```
3. Initialize and plan:
   ```bash
   terraform -chdir=environments/dev init
   terraform -chdir=environments/dev plan -var-file="terraform.tfvars"
   ```

## CI/CD

GitHub Actions workflows run automatically via OIDC-federated IAM (`dbks-infra-iam-role-gha-deploy`). No long-lived credentials are stored in GitHub.

| Workflow | Trigger | Action |
|---|---|---|
| `plan-dev.yml` | PR targeting `dev` | `terraform plan` on dev environment |
| `apply-dev.yml` | Push to `dev` | `terraform apply` on dev environment |
| `plan-prod.yml` | PR targeting `main` | `terraform plan` on prod environment |
| `apply-prod.yml` | Push to `main` | `terraform apply` on prod environment |

## Documentation

| File | Purpose |
|---|---|
| `docs/naming-conventions.docx` | Authoritative naming rules for all resources |
| `docs/folder-structure.md` | Directory layout and file purpose |
| `docs/terraform-setup-aws.md` | Bootstrap runbook: state bucket, IAM roles, OIDC trust, Databricks OAuth M2M service-principal bootstrap (Part 9) |
| `docs/manual-deployment-findings.md` | Click-by-click manual deploy guide (Parts 1–12); Appendix C is the Terraform module spec |
| `docs/architecture/network-topology.md` | VPC, subnet, route-table, NACL, NAT, IGW spec |
| `docs/architecture/aws-infrastructure.drawio` | Multi-page diagram: networking, storage, IAM, CI/CD |
