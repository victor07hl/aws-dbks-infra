---
name: aws-databricks-tf-deploy
description: Guide for deploying a Databricks Unity Catalog workspace on AWS using Terraform, with context for manual deployments.
---

You are an expert in deploying Databricks on AWS using Terraform. When invoked, help the user plan, write, or troubleshoot Terraform configuration for Databricks Unity Catalog workspaces on AWS.

---

## Terraform Deployment Guide

### Required Providers

```hcl
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
    }
    aws = {
      source  = "hashicorp/aws"
    }
  }
}
```

### Deployment Order

Always deploy resources in this dependency order:
1. **AWS IAM** — cross-account role for Databricks control plane
2. **AWS S3** — root storage bucket for the workspace
3. **Databricks credential config** — references the IAM role ARN
4. **Databricks storage config** — references the S3 bucket
5. **Databricks workspace** (`databricks_mws_workspaces`) — references credential + storage configs
6. **Metastore assignment** — assign the existing Unity Catalog metastore to the workspace
7. **Catalog + workspace binding** — create catalog, bind to workspace

### Key Terraform Resources

| Resource | Purpose |
|----------|---------|
| `databricks_mws_credentials` | Cross-account IAM role registration |
| `databricks_mws_storage_configurations` | S3 root bucket registration |
| `databricks_mws_workspaces` | Workspace provisioning |
| `databricks_metastore` | Unity Catalog metastore (one per region) |
| `databricks_metastore_assignment` | Bind metastore to workspace |
| `databricks_catalog` | Unity Catalog catalog |
| `databricks_catalog_workspace_binding` | Bind catalog to a specific workspace |

### IAM Cross-Account Role

The IAM role must trust the Databricks production AWS account (`414351767826`) with your Databricks account ID as the external ID:

```hcl
resource "aws_iam_role" "databricks_cross_account" {
  name = "databricks-cross-account-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::414351767826:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.databricks_account_id }
      }
    }]
  })
}
```

### S3 Root Bucket Policy

The bucket policy must allow the Databricks production account principal and deny DBFS access to Unity Catalog metastore paths:

```hcl
resource "aws_s3_bucket_policy" "workspace_root" {
  bucket = aws_s3_bucket.workspace_root.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::414351767826:root" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource  = [
          aws_s3_bucket.workspace_root.arn,
          "${aws_s3_bucket.workspace_root.arn}/*"
        ]
      }
    ]
  })
}
```

### Best Practices

- Use `data.databricks_current_user.me.alphanumeric` for dynamic naming to avoid conflicts.
- Set `autotermination_minutes = 20` on clusters for cost control.
- Always enable autoscaling with `min_workers` / `max_workers`.
- Use secrets management (`databricks_secret_scope`, `databricks_secret`) — never hardcode tokens.
- Store sensitive values in `terraform.tfvars` (gitignored).
- Use remote state (S3 + DynamoDB) for all shared environments.
- Run `terraform plan` before every `apply`.

---

## Manual Deployment Context

Use this section to explain or provide context when the user asks about the manual process or when comparing Terraform steps to console steps.

### Prerequisites (Manual or Terraform)

- Account admin in the Databricks account console
- AWS permissions: create IAM roles, S3 buckets, access policies
- VPC and NAT gateway available in the target region
- STS endpoint activated for your region (required for `us-west-2`)

### Step-by-Step Manual Flow

1. **Credential configuration** — Create a cross-account IAM role in AWS trusting `414351767826` with your Databricks account ID as the external ID. Copy the role ARN.
2. **Storage configuration** — Create an S3 bucket in the target region. Apply the Databricks bucket policy. Create a storage access IAM role trusting `arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole` (make it self-assuming). Attach S3 read/write policies.
3. **Workspace creation** — In the Databricks account console, go to Workspaces → Create Workspace. Provide name, region, credential config, and storage config. Configure optional settings (PrivateLink, CMK, enhanced security).
4. **Metastore assignment** — If a metastore exists in the region it is auto-assigned; otherwise create one first.
5. **Post-deployment** — Monitor status: `Provisioning → Running`. Then add users and configure Unity Catalog data governance.

### Workspace Status Flow

```
Provisioning → Running   ✓ success
Provisioning → Failed    ✗ check IAM role, S3 policy, VPC config
```

### Optional Advanced Settings

| Setting | When to use |
|---------|------------|
| Customer-managed VPC | When you need network isolation or custom CIDR |
| PrivateLink | For private access without traversing public internet |
| Customer-managed encryption keys (CMK) | Compliance requirements |
| Enhanced security & compliance | Regulated industries (HIPAA, FedRAMP) |

---

## This Project's Architecture

- **Metastore**: one, in `us-east-2`, shared across workspaces
- **Workspaces**: `dev` (branch: `dev`) and `prod` (branch: `main`)
- **Catalogs**: `dev` bound to workspace-dev, `prod` bound to workspace-prod
- **State**: remote state via S3 + DynamoDB per environment
- **CI/CD**: GitHub Actions — plan on PR, apply on merge
