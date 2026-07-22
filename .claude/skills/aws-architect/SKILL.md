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
Authoritative source: `docs/architecture/network-topology.md`. The dev environment is currently provisioned as:

```
VPC: dbks-infra            CIDR 10.0.0.0/16   (DNS resolution + DNS hostnames: ENABLED)
├── Public  subnet  dbks-infra-dev-public-subnet     10.0.0.0/24   us-east-2a (use2-az1)
├── Private subnet  dbks-infra-dev-private-subnet    10.0.1.0/24   us-east-2b (use2-az2)
└── Private subnet  dbks-infra-dev-private-subnet-2  10.0.2.0/24   us-east-2a (use2-az1)

Route tables
├── dbks-infra-dev-public-rt   → 0.0.0.0/0 via dbks-infra-dev-IGW,  10.0.0.0/16 local
│      assoc: dbks-infra-dev-public-subnet
└── dbks-infra-dev-private-rt  → 0.0.0.0/0 via dbks-infra-dev-NATG, 10.0.0.0/16 local
       assoc: dbks-infra-dev-private-subnet, dbks-infra-dev-private-subnet-2

Edge
├── Internet Gateway  dbks-infra-dev-IGW
└── NAT Gateway       dbks-infra-dev-NATG    (single, in public subnet — dev cost optimization)

DHCP option set: dbks-infra-dev-DHCP-option-set
       domain name: us-east-2.compute.internal
       domain name servers: AmazonProvidedDNS
```

### Rules
- Databricks nodes always go in private subnets (`-private-subnet`, `-private-subnet-2`)
- The two private subnets span 2 AZs (us-east-2a, us-east-2b) — required by Databricks for HA
- Public subnet hosts only the NAT Gateway and IGW attachment — never Databricks clusters
- Single NAT Gateway in dev (cost optimization). For prod, plan one NAT per AZ.
- Do not change subnet CIDRs without updating the network spec doc and the Databricks workspace network config
- Always use AmazonProvidedDNS via the DHCP option set — Databricks requires DNS resolution

### Network ACL (Main NACL — applies to all 3 subnets above)
Per spec, the main NACL is associated with the public subnet and both private subnets.

Inbound:
- Rule 99: Allow ALL from `0.0.0.0/0`
- Rule *: Deny ALL (default)

Outbound (explicit allow list — keep this aligned with the spec doc):
- Rule 99:  Allow ALL to `10.0.0.0/16` (intra-VPC)
- Rule 100: Allow TCP 443  to `0.0.0.0/0` (HTTPS — Databricks control plane, S3, STS)
- Rule 101: Allow TCP 3306 to `0.0.0.0/0` (Hive metastore / internal metadata)
- Rule 102: Allow TCP 8443 to `0.0.0.0/0` (Databricks secure cluster connectivity — HTTPS*)
- Rule 103: Allow TCP 8445 to `0.0.0.0/0` (Databricks SCC relay)
- Rule 104: Allow TCP 8444 to `0.0.0.0/0` (Databricks SCC relay)
- Rule *:   Deny ALL (default)

> Ports 8443/8444/8445 are Databricks-specific for secure cluster connectivity / control-plane relay. Do not remove them when tightening the NACL.

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
- Use a VPC endpoint for S3 to avoid NAT costs

---

## S3 bucket design

### Buckets needed for this project
Follow `docs/naming-conventions.docx`. Two buckets: a shared TF state bucket, plus one workspace bucket per environment. No separate metastore bucket.

```
dbks-infra-s3-tf-state                  # Terraform remote state — NO explicit encryption (project decision)
dbks-infra-{env}-s3-ws                  # Per-env workspace bucket — holds workspace artifacts AND UC managed data under /unity-catalog/*
```

### Scope notes
- No separate metastore bucket. The metastore is provisioned with no `storage_root`; UC managed data lands in each workspace's own bucket under `/unity-catalog/*`, with a bucket policy `Deny` on that prefix for the Databricks root principal to block legacy DBFS access.
- No per-catalog or per-schema managed-storage buckets — catalogs inherit storage from the workspace bucket via the metastore/UC binding.
- `dbks-infra-s3-tf-state` is explicitly created without an `aws_s3_bucket_server_side_encryption_configuration` block. AWS applies default SSE-S3 automatically; KMS CMK encryption is intentionally not used here.

### Mandatory settings for every bucket
```hcl
# Versioning
versioning {
  enabled = true
}

# Encryption — prefer SSE-KMS with a customer-managed key (CMK)
server_side_encryption_configuration {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cmk.arn
    }
    bucket_key_enabled = true
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

> AES256 is acceptable only for non-sensitive buckets. Default to KMS CMK.
>
> **Current project exception:** `dbks-infra-s3-tf-state` is provisioned with NO explicit encryption block (relying on AWS default SSE-S3). This is an intentional project-level simplification for the current iteration — do NOT auto-"fix" this by adding KMS or SSE-KMS.

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
All role names must follow `docs/naming-conventions.docx`:

```
dbks-infra-iam-role-gha-deploy       # GitHub Actions CI/CD (shared, OIDC trust)
dbks-infra-{env}-ws-role             # Databricks control plane / EC2 compute credential per env (modules/iam-credential)
dbks-{env}-trust-role-ws             # Unity Catalog storage trust role per env, self-assuming (modules/iam-storage)
```

---

## VPC endpoints

Always create a VPC endpoint for S3 to avoid NAT Gateway costs. This project has no DynamoDB usage (state locking is S3-native, `use_lockfile = true`), so no DynamoDB endpoint is needed:
```hcl
# S3 Gateway endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private.id]
}
```

Additionally create Interface endpoints (paid, ~$7/mo each) for services accessed from private subnets that do not have Gateway endpoints:
- `com.amazonaws.${region}.secretsmanager` — keep secret retrieval off the public internet
- `com.amazonaws.${region}.sts` — for AssumeRole / OIDC calls from within the VPC
- `com.amazonaws.${region}.kms` — only if workloads call KMS frequently from the VPC

---

## Secrets management

Never store credentials in `.tf` files, `terraform.tfvars`, or CI environment variables. Use AWS Secrets Manager.

### Secrets needed for this project
```
dbks-infra-{env}-sm-databricks-m2m     # Databricks OAuth M2M service-principal client_id + client_secret,
                                        # per env, dedicated CMK (modules/secrets-databricks-auth)
```

### Mandatory settings
```hcl
resource "aws_secretsmanager_secret" "this" {
  name                    = "dbks-infra-${var.environment}-sm-${var.descriptor}"
  kms_key_id              = aws_kms_key.cmk.arn   # CMK, not aws/secretsmanager default
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_rotation" "this" {
  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = aws_lambda_function.rotator.arn
  rotation_rules { automatically_after_days = 90 }
}
```

### Rules
- Always encrypt with a customer-managed KMS key (CMK), never the default `aws/secretsmanager` key
- Enable automatic rotation (max 90 days) for all machine credentials
- Read secrets at runtime via `data "aws_secretsmanager_secret_version"` — never hardcode values
- Scope `secretsmanager:GetSecretValue` to specific secret ARNs in IAM policies (no wildcards)

> **Current project exception:** `dbks-infra-{env}-sm-databricks-m2m` has no `aws_secretsmanager_secret_rotation` yet — the value is populated manually out-of-band (`docs/terraform-setup-aws.md` Part 9), and automatic rotation would need a custom Lambda that also rotates the corresponding secret on the Databricks side. Tracked as a follow-up before this goes to prod — don't auto-add rotation to this specific secret without that Lambda.

---

## KMS — customer-managed keys (CMK)

One CMK per environment for envelope encryption across S3, Secrets Manager, CloudWatch Logs, and EBS.

### Keys needed for this project
```
dbks-infra-{env}-kms-cmk   # Multi-service CMK (S3 + Secrets Manager + CW Logs + EBS)
```

### Mandatory settings
```hcl
resource "aws_kms_key" "cmk" {
  description             = "dbks-infra ${var.environment} multi-service CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true        # mandatory — yearly automatic rotation
  policy                  = data.aws_iam_policy_document.kms_policy.json
}

resource "aws_kms_alias" "cmk" {
  name          = "alias/dbks-infra-${var.environment}-kms-cmk"
  target_key_id = aws_kms_key.cmk.key_id
}
```

### Rules
- Always enable key rotation (`enable_key_rotation = true`)
- Deletion window minimum 30 days (prevents accidental destruction)
- Grant service principals (S3, Secrets Manager, CloudWatch Logs) via key policy `kms:ViaService` conditions
- Never share CMKs across environments — one CMK per env for blast-radius isolation

---

## CloudTrail — audit logging

Every account must have a multi-region trail capturing all management events.

### Mandatory settings
```hcl
resource "aws_cloudtrail" "this" {
  name                          = "dbks-infra-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cmk.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_cw.arn
}
```

### Rules
- Multi-region trail always (`is_multi_region_trail = true`)
- Log file validation always (`enable_log_file_validation = true`)
- Encrypt logs with the CMK (not AES256)
- Ship to CloudWatch Logs for real-time alerting on security events
- Log S3 bucket must have Object Lock or a deny-delete bucket policy to prevent tampering

---

## Architecture checklist

Before finalizing any design verify:
- [ ] At least 2 AZs used (dev: private subnets in us-east-2a + us-east-2b)
- [ ] Databricks nodes in private subnets only (`dbks-infra-dev-private-subnet`, `-private-subnet-2`)
- [ ] NAT Gateway exists for outbound internet (`dbks-infra-dev-NATG`, in public subnet)
- [ ] Public route table routes 0.0.0.0/0 → IGW; private route table routes 0.0.0.0/0 → NAT GW
- [ ] Main NACL outbound allows Databricks ports 443, 3306, 8443, 8444, 8445
- [ ] DHCP option set uses AmazonProvidedDNS (Databricks requires DNS resolution)
- [ ] S3 Gateway VPC endpoint created (free)
- [ ] Secrets Manager + STS Interface VPC endpoints created
- [ ] Security groups have self-referencing rules
- [ ] No 0.0.0.0/0 on inbound rules except load balancers
- [ ] All S3 buckets: SSE-KMS (CMK), versioning ON, public access BLOCKED
- [ ] All secrets in Secrets Manager with KMS CMK encryption + rotation
- [ ] KMS CMK has `enable_key_rotation = true`
- [ ] Multi-region CloudTrail with log file validation and KMS encryption
- [ ] IAM roles use OIDC or cross-account trust — never IAM users with static keys

---

## Region rules for this project

- Primary region: `us-east-2`
- All resources must be in us-east-2
- Databricks metastore must match workspace region
- S3 state bucket must be in us-east-2

---

## Availability and resilience

- NAT Gateway: dev runs a single NAT (`dbks-infra-dev-NATG`) in `dbks-infra-dev-public-subnet` for cost reasons — accept single-AZ NAT failure risk in dev. For prod, deploy one NAT per AZ.
- Private subnets span 2 AZs (us-east-2a, us-east-2b) so Databricks can place cluster nodes in either AZ even with the single-NAT egress.
- S3: always cross-region replication for prod state bucket
- State locking: S3 native (`use_lockfile = true`, Terraform ≥ 1.10) — no DynamoDB lock table

---

## Cost optimization rules

- Use the S3 VPC endpoint (Gateway type — free)
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
- Never skip the VPC endpoint for S3
- Never store credentials in `.tf`, `terraform.tfvars`, or CI env vars — use Secrets Manager
- Never use the default `aws/secretsmanager` or `aws/s3` KMS keys for sensitive data — always CMK
- Never disable CloudTrail or disable key rotation on KMS CMKs
- Never use names that violate `docs/naming-conventions.docx` — all resources must match `dbks-infra-*`
