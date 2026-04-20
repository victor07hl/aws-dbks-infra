---
name: aws-architect
description: >
  Senior AWS architect skill for designing and reviewing cloud infrastructure.
  Use this skill whenever the user needs to design, review, or make decisions
  about AWS architecture including: VPC design, subnet strategy, security groups,
  IAM roles and policies, S3 bucket design, networking, OIDC federation,
  cross-account access, availability zones, NAT gateways, VPC endpoints,
  or any AWS infrastructure design decision. Always load this skill when
  designing or reviewing AWS architecture — even for single-resource decisions.
---

# AWS Architect Skill

## Design philosophy
- Security first — least privilege on every resource
- Everything private by default — no public exposure unless explicitly required
- High availability — always span at least 2 availability zones
- Cost awareness — right-size resources, use VPC endpoints to avoid NAT costs
- Auditability — every resource tagged, every action logged in CloudTrail

---

## VPC design rules

### Structure for this project
```
VPC: 10.0.0.0/16
├── Private Subnet AZ-a: 10.0.1.0/24  (Databricks cluster nodes)
├── Private Subnet AZ-b: 10.0.2.0/24  (Databricks cluster nodes)
├── Public Subnet AZ-a:  10.0.3.0/24  (NAT Gateway)
└── Public Subnet AZ-b:  10.0.4.0/24  (NAT Gateway)
```

### Rules
- Databricks nodes always go in private subnets
- NAT Gateway in public subnet for outbound internet access
- Never put Databricks cluster nodes in public subnets
- Always use at least 2 AZs for high availability
- Minimum /26 subnet size for Databricks (needs room for cluster scaling)

---

## Security group rules

### Databricks cluster security group
```
Inbound:
- Self-referencing rule (cluster-to-cluster communication)
- Port 443 from VPC CIDR (HTTPS)
- Port 3306 from VPC CIDR (internal)

Outbound:
- All traffic to 0.0.0.0/0 (required for Databricks control plane)
```

### Rules
- Always use self-referencing security group rules for cluster communication
- Never open SSH (port 22) to 0.0.0.0/0
- Use VPC endpoints for S3 and DynamoDB to avoid NAT costs

---

## S3 bucket design

### Buckets needed for this project
```
aws-dbks-uc-terraform-state     # Terraform remote state
aws-dbks-uc-dev-storage         # Dev external storage
aws-dbks-uc-prod-storage        # Prod external storage
```

### Mandatory settings for every bucket
```hcl
# Versioning
versioning {
  enabled = true
}

# Encryption
server_side_encryption_configuration {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

---

## IAM design rules

### Least privilege principle
- Never use wildcard `*` for actions unless absolutely necessary
- Always scope resource ARNs to specific buckets, tables, or roles
- Use conditions to restrict access by region, account, or VPC

### Cross-account trust for Databricks
```hcl
data "aws_iam_policy_document" "databricks_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::414351767826:root"]  # Databricks account
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}
```

### OIDC trust for GitHub Actions
```hcl
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}
```

### IAM roles needed for this project
```
github-actions-terraform-role     # Used by GitHub Actions CI/CD
databricks-cross-account-role     # Databricks control plane access
databricks-dev-storage-role       # Dev S3 bucket access for Unity Catalog
databricks-prod-storage-role      # Prod S3 bucket access for Unity Catalog
```

---

## VPC endpoints

Always create VPC endpoints for these services to avoid NAT Gateway costs:
```hcl
# S3 Gateway endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private.id]
}

# DynamoDB Gateway endpoint (free)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private.id]
}
```

---

## Networking checklist

Before finalizing any VPC design verify:
- [ ] At least 2 AZs used
- [ ] Databricks nodes in private subnets only
- [ ] NAT Gateway exists for outbound internet
- [ ] S3 VPC endpoint created
- [ ] DynamoDB VPC endpoint created
- [ ] Security groups have self-referencing rules
- [ ] No 0.0.0.0/0 on inbound rules except load balancers

---

## Region rules for this project

- Primary region: `us-east-2`
- All resources must be in us-east-2
- Databricks metastore must match workspace region
- S3 state bucket must be in us-east-2

---

## Availability and resilience

- NAT Gateway: one per AZ for high availability (use single NAT for dev to save cost)
- S3: always cross-region replication for prod state bucket
- DynamoDB: on-demand billing for lock table (no capacity planning needed)

---

## Cost optimization rules

- Use S3 + DynamoDB VPC endpoints (Gateway type — free)
- Use single NAT Gateway for dev environment
- Use two NAT Gateways for prod (one per AZ)
- Tag all resources for cost allocation
- Enable S3 Intelligent-Tiering for storage buckets

---

## What NOT to do

- Never create public subnets without a NAT Gateway
- Never put Databricks nodes in public subnets
- Never use root AWS account credentials in Terraform
- Never create IAM users with programmatic access — use roles and OIDC
- Never open port 22 (SSH) to 0.0.0.0/0
- Never create S3 buckets without encryption and public access block
- Never skip VPC endpoints for S3 and DynamoDB
