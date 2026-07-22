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
1. **AWS VPC + networking** — VPC, subnets, route tables, IGW, NAT GW, NACL, DHCP option set (per `docs/architecture/network-topology.md`)
2. **AWS IAM** — cross-account role for Databricks control plane
3. **AWS S3 workspace bucket** — one bucket per environment; holds workspace artifacts AND (since the metastore has no `storage_root`) Unity Catalog managed data under `/unity-catalog/*`
4. **Databricks credential config** — references the IAM role ARN
5. **Databricks network config** (`databricks_mws_networks`) — references VPC ID and the two private subnet IDs
6. **Databricks workspace** (`databricks_mws_workspaces`) — references credential config + network config + the workspace bucket from step 3
7. **Metastore** (`databricks_metastore`) — no `storage_root` (project decision); UC managed data lands in each workspace's own bucket
8. **Metastore assignment** — bind metastore to each workspace
9. **Catalog + workspace binding** — create catalog (inherits storage from metastore), bind to workspace

### Key Terraform Resources

| Resource | Purpose |
|----------|---------|
| `databricks_mws_credentials` | Cross-account IAM role registration |
| `databricks_mws_workspaces` | Workspace provisioning |
| `databricks_metastore` | Unity Catalog metastore (one per region) — no `storage_root` configured; UC managed data lands in the workspace bucket |
| `databricks_metastore_assignment` | Bind metastore to workspace |
| `databricks_catalog` | Unity Catalog catalog (inherits managed storage from metastore) |
| `databricks_catalog_workspace_binding` | Bind catalog to a specific workspace |

### Project scope notes (current iteration)
- S3 buckets: `dbks-infra-s3-tf-state` (no encryption, shared) plus one `dbks-infra-{env}-s3-ws` per environment — no separate metastore bucket.
- The metastore has no `storage_root` at all — UC managed data lands in each workspace's own bucket under `/unity-catalog/*`, with a bucket policy `Deny` on that prefix for the Databricks root principal to block legacy DBFS access.
- AWS-side prerequisites (network, IAM, S3, secrets) are implemented via `modules/network`, `modules/iam-credential`, `modules/s3-workspace`, `modules/iam-storage`, `modules/secrets-databricks-auth`; the Databricks-side resources (`databricks_mws_workspaces`, `databricks_metastore`, catalog) are not yet wired into `environments/dev/main.tf`.

### Network topology (dev) — must match `docs/architecture/network-topology.md`

Customer-managed VPC. Databricks workspace network config must reference the VPC and the **two private subnets only**.

| Resource | Name | CIDR / detail | AZ |
|---|---|---|---|
| VPC | `dbks-infra` | `10.0.0.0/16`, DNS resolution + hostnames ON | — |
| Public subnet | `dbks-infra-dev-public-subnet` | `10.0.0.0/24` | us-east-2a |
| Private subnet 1 | `dbks-infra-dev-private-subnet` | `10.0.1.0/24` | us-east-2b |
| Private subnet 2 | `dbks-infra-dev-private-subnet-2` | `10.0.2.0/24` | us-east-2a |
| Public route table | `dbks-infra-dev-public-rt` | `0.0.0.0/0` → IGW; `10.0.0.0/16` local | — |
| Private route table | `dbks-infra-dev-private-rt` | `0.0.0.0/0` → NAT GW; `10.0.0.0/16` local | — |
| Internet Gateway | `dbks-infra-dev-IGW` | — | — |
| NAT Gateway | `dbks-infra-dev-NATG` | single, in public subnet | us-east-2a |
| DHCP option set | `dbks-infra-dev-DHCP-option-set` | domain `us-east-2.compute.internal`, AmazonProvidedDNS | — |

```hcl
resource "databricks_mws_networks" "this" {
  account_id   = var.databricks_account_id
  network_name = "dbks-infra-dev-mws-network"
  vpc_id       = aws_vpc.this.id
  subnet_ids   = [
    aws_subnet.private.id,    # dbks-infra-dev-private-subnet    (us-east-2b)
    aws_subnet.private_2.id,  # dbks-infra-dev-private-subnet-2  (us-east-2a)
  ]
  security_group_ids = [aws_security_group.workspace.id]
}
```

#### NACL — required outbound ports for Databricks
The main NACL is associated with all 3 subnets. Outbound must allow:

| Rule | Port | Purpose |
|---|---|---|
| 99  | ALL to `10.0.0.0/16` | intra-VPC traffic |
| 100 | TCP 443 | HTTPS — Databricks control plane, S3, STS |
| 101 | TCP 3306 | Hive metastore / internal metadata |
| 102 | TCP 8443 | Databricks secure cluster connectivity (HTTPS*) |
| 103 | TCP 8445 | Databricks SCC relay |
| 104 | TCP 8444 | Databricks SCC relay |

If you tighten the NACL, **never drop 8443/8444/8445** — clusters will fail to attach to the control plane.

#### Single-NAT trade-off (dev)
There is one NAT Gateway in `us-east-2a`. The `us-east-2b` private subnet egresses through it cross-AZ — accept the data-transfer cost and single-AZ failure risk in dev. For prod, deploy one NAT per AZ and one private route table per AZ.

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
- Use remote state (S3, native locking via `use_lockfile = true`, Terraform ≥ 1.10) for all shared environments — no DynamoDB lock table (project decision).
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
- **State**: remote state via S3 per environment, S3 native locking (`use_lockfile = true`) — no DynamoDB
- **CI/CD**: GitHub Actions — plan on PR, apply on merge
