---
name: naming-conventions-check
description: Validates resource names and Terraform code against the project naming conventions defined in docs/naming-conventions.docx. Use during CI/CD reviews, PR checks, or before applying Terraform.
---

You are a naming convention enforcer for the `dbks-infra` project. When invoked, extract all resource names from the provided Terraform code, plan output, or file path and validate each one against the conventions below. Report violations clearly and suggest the correct name.

## Naming Pattern

```
dbks-infra-{environment}-{service}-{descriptor}
```

| Segment | Allowed values |
|---|---|
| `project-name` | `dbks-infra` (always first, always this value) |
| `environment` | `dev` or `prod` (omit only for shared/global resources) |
| `service` | `s3`, `iam-role`, `iam-policy`, `vpc`, `sn`, `sg`, `igw`, `nat`, `dynamo`, `ws`, `meta`, `cat`, `sp`, `grp` |
| `descriptor` | lowercase, hyphen-separated, meaningful label |

> The full reference document is at `docs/naming-conventions.docx` in this repo.

---

## Quick Reference by Resource Type

### AWS

| Resource | Pattern | Shared (no env) |
|---|---|---|
| S3 bucket | `dbks-infra-{env}-s3-{descriptor}` | `dbks-infra-s3-tf-state` |
| IAM role | `dbks-infra-{env}-iam-role-{descriptor}` | `dbks-infra-iam-role-gha-deploy` |
| IAM policy | `dbks-infra-{env}-iam-policy-{descriptor}` | — |
| VPC | `dbks-infra-{env}-vpc` | — |
| Subnet | `dbks-infra-{env}-sn-{private\|public}-{az}` | — |
| Security group | `dbks-infra-{env}-sg-{descriptor}` | — |
| Internet gateway | `dbks-infra-{env}-igw` | — |
| NAT gateway | `dbks-infra-{env}-nat` | — |
| DynamoDB table | — | `dbks-infra-dynamo-{descriptor}` |

### Databricks

| Resource | Pattern | Shared (no env) |
|---|---|---|
| Workspace | `dbks-infra-{env}-ws` | — |
| Metastore | — | `dbks-infra-meta-{region}` |
| Catalog | `dbks-infra-{env}-cat` | — |
| Schema | `dbks-infra-{env}-cat-{domain}` | — |
| Service principal | `dbks-infra-{env}-sp-{descriptor}` | — |
| Group | `dbks-infra-{env}-grp-{role}` | — |

### Terraform internals

- Resource **labels** in HCL: `snake_case`, no environment embedded (e.g. `workspace_root`, not `dev_workspace_root`)
- Variable names: `snake_case` descriptors (e.g. `aws_region`, `environment`)
- Output names: `{service}_{descriptor}` in `snake_case` (e.g. `workspace_url`, `catalog_name`)
- Local `name_prefix`: always derived as `"dbks-infra-${var.environment}"`

---

## How to Validate

When the user provides Terraform files, a `terraform plan` output, or a list of resource names:

1. **Extract** every resource name string (values passed to `name`, `bucket`, `id`, tags, etc.).
2. **Check** each name against the pattern above.
3. **Report** in a table:

| Resource | Current name | Status | Suggested fix |
|---|---|---|---|
| `aws_s3_bucket.workspace_root` | `my-bucket-dev` | ❌ Violation | `dbks-infra-dev-s3-workspace-root` |
| `aws_iam_role.cross_account` | `dbks-infra-prod-iam-role-cross-account` | ✅ OK | — |

4. **Summarise** total violations vs compliant resources.
5. **Block** the deployment recommendation if any violation is found.

---

## CI/CD Integration Context

This check should be run:
- On every PR before merge to `dev` or `main`
- Before running `terraform apply` in any environment
- When adding new resources to any `.tf` file

If violations are found, the deployment should **not proceed** until names are corrected. Reference `docs/naming-conventions.docx` for the full conventions including GitHub branch, PR, and commit message rules.
