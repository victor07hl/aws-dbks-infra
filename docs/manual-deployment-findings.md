# Manual Deployment Findings

> Captures every component, configuration, and lesson learned from the manual
> Databricks-on-AWS deployment in the dev environment, so that the Terraform
> implementation can reproduce it with confidence.
>
> **Source of truth for diagrams:** `docs/architecture/aws-infrastructure.drawio`
> (pages: `dbks-infra-networking`, `workspace structure`, `components infra`).
>
> **Scope:** dev environment only. Prod values are listed where they are already
> decided in the architecture; everything else stays out of scope until prod is
> manually deployed.
>
> **Format note:** ticket IT-20 asked for `.docx`; this is delivered as Markdown
> for parity with `docs/folder-structure.md` and to keep diffs readable in PRs.

---

## 1. AWS resources — exact configurations

### 1.1 VPC

| Field | Value |
|---|---|
| Name | `dbks-infra-dev-vpc` (display name: `dbks-infra` in the drawio) |
| VPC ID | `vpc-0c0888b82c6975777` |
| CIDR | `10.0.0.0/16` |
| DNS resolution | Enabled |
| DNS hostnames | Enabled |
| Region | `us-east-2` |

### 1.2 Subnets

| Name | CIDR | AZ | Type |
|---|---|---|---|
| `dbks-infra-dev-public-subnet` | `10.0.0.0/24` | `us-east-2a` (use2-az1) | Public |
| `dbks-infra-dev-private-subnet` | `10.0.1.0/24` | `us-east-2b` (use2-az2) | Private |
| `dbks-infra-dev-private-subnet-2` | `10.0.2.0/24` | `us-east-2a` (use2-az1) | Private |

### 1.3 Route tables

**`dbks-infra-dev-public-rt`** — associated with `dbks-infra-dev-public-subnet`

| Destination | Target |
|---|---|
| `10.0.0.0/16` | local |
| `0.0.0.0/0` | `dbks-infra-dev-IGW` |

**`dbks-infra-dev-private-rt`** — associated with both private subnets

| Destination | Target |
|---|---|
| `10.0.0.0/16` | local |
| `0.0.0.0/0` | `dbks-infra-dev-NATG` |

### 1.4 Internet Gateway

| Field | Value |
|---|---|
| Name | `dbks-infra-dev-IGW` |
| State | Attached to `dbks-infra-dev-vpc` |

### 1.5 NAT Gateway

| Field | Value |
|---|---|
| Name | `dbks-infra-dev-NATG` |
| Subnet | `dbks-infra-dev-public-subnet` |
| Primary private IPv4 | `10.0.0.79` |
| Primary public IPv4 (EIP) | `16.59.107.134` |
| Primary network interface | `dbks-infra-dev-primary-network-interface` |
| Count | **1** (cost optimization for dev — accept single-AZ NAT failure risk) |

### 1.6 Network ACL (Main NACL)

Associated subnets: `dbks-infra-dev-public-subnet`, `dbks-infra-dev-private-subnet`, `dbks-infra-dev-private-subnet-2`.

**Inbound**

| Rule # | Type | Protocol | Port | Source | Action |
|---|---|---|---|---|---|
| 99 | All traffic | All | All | `0.0.0.0/0` | Allow |
| * | All traffic | All | All | `0.0.0.0/0` | Deny |

**Outbound**

| Rule # | Type | Protocol | Port | Destination | Action | Why |
|---|---|---|---|---|---|---|
| 99  | All       | All | All  | `10.0.0.0/16` | Allow | Intra-VPC |
| 100 | HTTPS     | TCP | 443  | `0.0.0.0/0`   | Allow | Databricks control plane, S3, STS |
| 101 | MySQL     | TCP | 3306 | `0.0.0.0/0`   | Allow | Internal Hive metastore |
| 102 | HTTPS*    | TCP | 8443 | `0.0.0.0/0`   | Allow | Databricks secure cluster connectivity |
| 103 | Custom TCP| TCP | 8445 | `0.0.0.0/0`   | Allow | Databricks SCC relay |
| 104 | Custom TCP| TCP | 8444 | `0.0.0.0/0`   | Allow | Databricks SCC relay |
| *   | All       | All | All  | `0.0.0.0/0`   | Deny  | Default deny |

### 1.7 DHCP option set

| Field | Value |
|---|---|
| Name | `dbks-infra-dev-DHCP-option-set` |
| Domain name | `us-east-2.compute.internal` |
| Domain name servers | `AmazonProvidedDNS` |

### 1.8 S3 buckets

| Bucket | Purpose | Encryption | Versioning | Public access |
|---|---|---|---|---|
| `dbks-infra-s3-tf-state` | Terraform remote state | Default SSE-S3 (no explicit block — intentional) | ON | BLOCKED |
| `dbks-infra-dev-s3-metastore` | Unity Catalog metastore-level managed storage (dev) | SSE-KMS (CMK) | ON | BLOCKED |
| `dbks-infra-dev-s3-ws` | Databricks workspace artifacts (dev) | SSE-KMS (CMK) | ON | BLOCKED |

> Per project decision (see `aws-architect` skill), `dbks-infra-s3-tf-state`
> intentionally has no explicit `aws_s3_bucket_server_side_encryption_configuration`.

### 1.9 Outbound packet flow (verified manually)

```
EC2 (private subnet, src 10.0.1.x or 10.0.2.x)
   └─► dbks-infra-dev-private-rt  (0.0.0.0/0 → NAT)
        └─► dbks-infra-dev-NATG   (10.0.0.79 → 16.59.107.134)
             └─► dbks-infra-dev-public-rt  (0.0.0.0/0 → IGW)
                  └─► dbks-infra-dev-IGW
                       └─► Internet (e.g. 8.8.8.8 / Databricks control plane)
```

---

## 2. IAM roles and policies — exact permissions

> Trust policies, action lists, and ARN scoping below reflect what was attached
> in the manual console deployment. Capture the exact JSON from the AWS console
> on next refresh and paste into the linked sections; the structure here is the
> shape every role must have.

### 2.1 `dbks-infra-dev-ws-role` — EC2 compute role for Databricks clusters

- Attached to `dev-ws-cloud-credential` (Databricks credential configuration).
- Used by Databricks to launch EC2 nodes inside the customer-managed VPC.
- Trust: Databricks production account `414351767826` with `sts:ExternalId == <databricks_account_id>`.
- Permissions: EC2 lifecycle, ENI management, security-group reference, tagging, KMS decrypt for EBS, plus the published Databricks cross-account policy.

### 2.2 `dbks-dev-trust-role-ws` — Workspace storage trust role

- Attached to `dev-ws-storage` (Databricks storage configuration).
- Trusts the same Databricks production account with the External ID condition.
- Permissions: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, `s3:GetBucketLocation` scoped to `dbks-infra-dev-s3-ws`; SQS for workspace event notifications.

### 2.3 Roles to add for the Terraform iteration

These are not in the manual deployment but the architecture requires them:

| Role | Purpose |
|---|---|
| `dbks-infra-iam-role-gha-deploy` | GitHub Actions OIDC deployment role |
| `dbks-infra-{env}-iam-role-cross-account` | Per-env cross-account role for the Databricks control plane |
| `dbks-infra-{env}-iam-role-uc-storage` | Per-env Unity Catalog S3 access role |

---

## 3. Databricks resources — settings

### 3.1 Account-level

| Resource | Value |
|---|---|
| Databricks account ID | _stored in Secrets Manager (`dbks-infra-{env}-sm-account-creds`)_ |
| Databricks AWS account principal | `arn:aws:iam::414351767826:root` |
| Region | `us-east-2` |

### 3.2 Workspace `dbks-infra-dev-ws`

| Setting | Value |
|---|---|
| Workspace deployment name | `dbc-03363fa1-0d7a` |
| Region | `us-east-2` |
| Pricing tier | Premium (required for Unity Catalog) |
| Network type | Customer-managed VPC |
| Bound branch | `dev` |
| Bound environment | DEV |

#### Workspace configurations attached

| Configuration | Name | Notes |
|---|---|---|
| Compute credentials | `dev-ws-cloud-credential` | Wraps `dbks-infra-dev-ws-role` ARN |
| Network configuration | `dbks-infra-dev-network-config` | Points at `vpc-0c0888b82c6975777`, the two private subnets, and the workspace security group |
| Workspace storage | `dev-ws-storage` | Wraps `dbks-infra-dev-s3-ws` and `dbks-dev-trust-role-ws` |

### 3.3 Unity Catalog topology

```
Metastore: dbks-infra-meta-us-east-2  (region us-east-2, shared)
   ├─ Workspace: dbks-infra-dev-ws    → Catalog: dbks-infra-dev-cat   (workspace-bound)
   └─ Workspace: dbks-infra-prod-ws   → Catalog: dbks-infra-prod-cat  (workspace-bound, planned)
```

Per-catalog schemas (identical for dev and prod):

| Schema | Purpose |
|---|---|
| `raw` | Raw data landed as-is from sources |
| `bronze` | Ingested, minimally transformed |
| `silver` | Cleaned, conformed, enriched |
| `gold` | Aggregated, business-ready |
| `stage` | Temporary processing area |

Metastore storage backing: `dbks-infra-{env}-s3-metastore` per environment.

Reference styles:
- Same-workspace: `dbks-infra-dev-cat.silver.fact_sells`
- Cross-workspace (exceptional): `DEV.dbks-infra-dev-cat.silver.fact_sells`

### 3.4 Identities (provisioned per workspace)

| Type | Dev | Prod |
|---|---|---|
| Service principal | `dbks-infra-dev-sp-deploy` | `dbks-infra-prod-sp-deploy` |
| Service principal | `dbks-infra-dev-sp-etl` | `dbks-infra-prod-sp-etl` |
| Group | `dbks-infra-dev-grp-data-engineers` | `dbks-infra-prod-grp-data-engineers` |
| Group | `dbks-infra-dev-grp-analysts` | `dbks-infra-prod-grp-analysts` |

---

## 4. Issues encountered and how they were resolved

> Backfill from console history / personal notes as the manual deployment
> closes out (IT-15). Pre-seeded with the categories most likely to bite us
> based on the configuration above.

| # | Symptom | Root cause | Resolution |
|---|---|---|---|
| 1 | _TBD_ | _TBD_ | _TBD_ |

Common gotchas for this topology to watch for during the writeup:
- Cluster fails to come up → confirm NACL outbound rules 102/103/104 are present (8443/8444/8445).
- Workspace creation succeeds but UC unavailable → confirm metastore exists in `us-east-2` and is assigned to the workspace.
- `AccessDenied` on S3 from a cluster → confirm `dbks-dev-trust-role-ws` trust policy still has the ExternalId condition and that the workspace storage configuration was not recreated.
- Cross-AZ NAT cost spike → expected with single NAT in `us-east-2a`; revisit for prod (one NAT per AZ).

---

## 5. Recommendations for the Terraform implementation

1. **Module boundaries**
   - `modules/network` — VPC, subnets, route tables, IGW, NAT GW, NACL, DHCP options.
   - `modules/iam` — workspace EC2 role, S3 trust role, future GitHub OIDC role.
   - `modules/s3` — `dbks-infra-{env}-s3-ws`, `dbks-infra-{env}-s3-metastore`, plus the existing `dbks-infra-s3-tf-state`.
   - `modules/databricks-workspace` — credential, network, storage configurations + workspace + metastore assignment + catalog binding.
   - Top-level envs (`envs/dev`, `envs/prod`) compose the modules.

2. **Variables, not literals**
   - `vpc_cidr`, `private_subnet_cidrs`, `public_subnet_cidrs`, `azs`, `region` must all be variables — do not hardcode `10.0.0.0/16` or `us-east-2` in resources.
   - The Databricks production account `414351767826` should be a `locals.databricks_aws_account_id` constant in one place.

3. **State and locking**
   - Continue using `dbks-infra-s3-tf-state` (default SSE-S3, no KMS) per project decision.
   - Add a DynamoDB lock table; keep on-demand billing.

4. **Secrets**
   - Migrate `databricks_account_id`, account-level client secret, and any workspace PATs from local notes / `terraform.tfvars` into `dbks-infra-{env}-sm-*` Secrets Manager entries with CMK encryption + 90-day rotation.

5. **VPC endpoints (add at TF time, were not in the manual deploy)**
   - Gateway: S3, DynamoDB.
   - Interface: Secrets Manager, STS, KMS.
   - Reduces NAT data-processing cost and keeps secret retrieval off the public internet.

6. **NACL discipline**
   - Codify rules 100–104 as a `for_each` map keyed by purpose (`https`, `metastore-3306`, `scc-8443`, `scc-8445`, `scc-8444`) so a future engineer cannot delete a Databricks-required port without it being obvious in the diff.

7. **Single vs multi-NAT**
   - Keep single NAT in `dbks-infra-dev-NATG` for dev.
   - For prod: one NAT per AZ + one private route table per AZ. Parameterize `nat_gateway_count` in the network module.

8. **Naming**
   - Every resource above already matches `dbks-infra-{env}-*`. Wire the naming convention through a `locals.name_prefix = "dbks-infra-${var.environment}"` and concat from there to avoid drift.

9. **Cross-account trust**
   - Always include the `sts:ExternalId` condition on roles trusted by `arn:aws:iam::414351767826:root`. Do not omit it — the manual setup includes it and the Databricks docs require it.

10. **Workspace deployment name**
    - `dbc-03363fa1-0d7a` was assigned by Databricks during manual creation. The Terraform run will produce a new deployment name — make sure downstream references use the `databricks_mws_workspaces.this.workspace_url` output instead of any hardcoded value.

---

## Appendix A — Resource name reference

| Layer | Resource | Name |
|---|---|---|
| VPC | VPC | `dbks-infra-dev-vpc` (`vpc-0c0888b82c6975777`) |
| VPC | Public subnet | `dbks-infra-dev-public-subnet` |
| VPC | Private subnet 1 | `dbks-infra-dev-private-subnet` |
| VPC | Private subnet 2 | `dbks-infra-dev-private-subnet-2` |
| VPC | Public route table | `dbks-infra-dev-public-rt` |
| VPC | Private route table | `dbks-infra-dev-private-rt` |
| VPC | IGW | `dbks-infra-dev-IGW` |
| VPC | NAT GW | `dbks-infra-dev-NATG` |
| VPC | DHCP option set | `dbks-infra-dev-DHCP-option-set` |
| IAM | Workspace EC2 role | `dbks-infra-dev-ws-role` |
| IAM | Storage trust role | `dbks-dev-trust-role-ws` |
| S3 | TF state | `dbks-infra-s3-tf-state` |
| S3 | Workspace artifacts | `dbks-infra-dev-s3-ws` |
| S3 | UC metastore (dev) | `dbks-infra-dev-s3-metastore` |
| Databricks | Credential config | `dev-ws-cloud-credential` |
| Databricks | Network config | `dbks-infra-dev-network-config` |
| Databricks | Storage config | `dev-ws-storage` |
| Databricks | Workspace | `dbks-infra-dev-ws` (`dbc-03363fa1-0d7a`) |
| Databricks | Metastore | `dbks-infra-meta-us-east-2` |
| Databricks | Catalog (dev) | `dbks-infra-dev-cat` |
