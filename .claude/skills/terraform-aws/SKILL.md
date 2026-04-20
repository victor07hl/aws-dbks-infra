---
name: terraform-aws
description: >
  Expert Terraform skill for AWS infrastructure. Use this skill whenever
  the user wants to write, review, debug, or improve Terraform code targeting
  AWS. Triggers on: writing .tf files, creating modules, configuring providers,
  managing remote state, writing variables/outputs, structuring environments,
  or any AWS infrastructure-as-code task. Always load this skill before
  generating any Terraform file for AWS — even for simple resources.
---

# Terraform on AWS — Best Practices Skill

## Core principles
- Every resource must be inside a module — no resources in root except module calls
- Always use remote state (S3 + DynamoDB locking)
- Never hardcode values — use variables for everything environment-specific
- All sensitive values come from environment variables or AWS Secrets Manager
- Run `terraform validate` and `terraform plan` before every apply
- Use `terraform fmt` on all files before committing

---

## File structure rules

Every module must have exactly these files:
```
module-name/
├── main.tf        # resources only
├── variables.tf   # input variables with descriptions and types
├── outputs.tf     # output values
└── versions.tf    # required providers and versions
```

Environment folders call modules:
```
environments/
├── dev/
│   ├── main.tf         # module calls with dev values
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars  # dev-specific values (gitignored)
└── prod/
    ├── main.tf         # module calls with prod values
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars  # prod-specific values (gitignored)
```

---

## Provider configuration

Always define two providers for Databricks projects:
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.39"
    }
  }
  backend "s3" {
    bucket         = var.state_bucket
    key            = "terraform.tfstate"
    region         = var.region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.common_tags
  }
}
```

---

## Variables rules

Every variable must have:
- `description` — what it is used for
- `type` — always explicit, never omit
- `default` — only for non-sensitive, optional values

```hcl
variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}
```

---

## Outputs rules

Every output must have:
- `description` — what the value represents
- `sensitive = true` — for any secret, key, password, or token

```hcl
output "workspace_url" {
  description = "Databricks workspace URL"
  value       = databricks_mws_workspaces.this.workspace_url
}
```

---

## Tagging rules

Always apply common tags to every AWS resource via default_tags:
```hcl
locals {
  common_tags = {
    Project     = "aws-dbks-infra"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "data-engineering"
    Region      = var.region
  }
}
```

---

## Security rules

- S3 buckets must always have:
  - `versioning enabled`
  - `server_side_encryption_configuration` with AES256 or aws:kms
  - `block_public_acls = true`
  - `block_public_policy = true`
  - `ignore_public_acls = true`
  - `restrict_public_buckets = true`

- IAM roles must always follow least privilege — no `*` actions unless justified
- Never use `AdministratorAccess` managed policy
- Always use `data` sources to reference existing resources instead of hardcoding ARNs

---

## State management rules

- One state file per environment (dev and prod are completely separate)
- State bucket must have versioning and encryption enabled
- DynamoDB table for locking must use `LockID` as partition key (String)
- Never store state locally — always use S3 backend

---

## Module call pattern

```hcl
module "aws_base" {
  source      = "../../modules/aws-base"
  environment = var.environment
  region      = var.region
  tags        = local.common_tags
}

module "aws_storage" {
  source      = "../../modules/aws-storage"
  environment = var.environment
  region      = var.region
  vpc_id      = module.aws_base.vpc_id
  tags        = local.common_tags
}
```

---

## What NOT to do

- Never use `terraform taint` — use `-replace` flag instead
- Never commit `terraform.tfvars` — always gitignore it
- Never commit `.terraform/` directory
- Never use `count` for resources that have identity — use `for_each` instead
- Never put secrets in variable default values
- Never use `local-exec` provisioner unless absolutely necessary
