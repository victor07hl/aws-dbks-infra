# Manual Deployment Guide — Databricks Unity Catalog on AWS (dev)

This guide walks you through manually mounting a Databricks Unity Catalog
workspace on AWS, end to end. It is written so a new data engineer can follow
it click-by-click and end up with a working `DEV` workspace.

The order matters: every Databricks console step depends on AWS resources
created in earlier sections. **Do not skip ahead.**

> **Authoritative references**
> - [Create a Unity Catalog workspace — Customer-managed VPC with default restrictions](https://docs.databricks.com/aws/en/admin/workspace/create-uc-workspace?language=Customer-managed%C2%A0VPC%C2%A0with%C2%A0default%C2%A0restrictions#credential)
> - [Customer-managed VPC — networking spec (subnet-level NACLs)](https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc#subnet-level-network-acls)
>
> **Diagrams:** `docs/architecture/aws-infrastructure.drawio` (pages
> `dbks-infra-networking`, `workspace structure`, `components infra`).

---

## Before you start

You need:

- AWS console access in the target account, with permission to create VPCs,
  subnets, IAM roles, and S3 buckets.
- Databricks **account console** access at <https://accounts.cloud.databricks.com>
  (account-admin role — workspace-admin is not enough for any of these steps).
- Your **Databricks account ID** (you'll grab it in Step 2.1).
- The two console tabs open side-by-side will save you a lot of time.

Region for everything below: **`us-east-2`**.

### Constants you'll paste many times

| What | Value | Where it appears |
|---|---|---|
| Databricks AWS production account | `414351767826` | Trust policies, S3 bucket policies |
| UC master role ARN | `arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL` | Storage role trust policy |
| Region | `us-east-2` | Every AWS resource |
| Databricks AMI source account | `601306020600` | Reference only (no action needed) |

### What you'll build (deployment order)

Each row is a discrete step. By the time you finish row 11, the workspace is
running and a new data engineer can log in.

| # | Where | What you create | Project name |
|---|---|---|---|
| 1 | AWS console | VPC + subnets + RTs + IGW + NAT + NACL + SG + DHCP | `dbks-infra-dev-vpc` |
| 2 | AWS console | Cross-account IAM role for the Databricks control plane | `dbks-infra-dev-ws-role` |
| 3 | AWS console | Workspace S3 bucket + bucket policy | `dbks-infra-dev-s3-ws` |
| 4 | AWS console | Storage IAM trust role (self-assuming) | `dbks-dev-trust-role-ws` |
| 5 | Databricks account console | Credential configuration | `dev-ws-cloud-credential` |
| 6 | Databricks account console | Network configuration | `dbks-infra-dev-network-config` |
| 7 | Databricks account console | Storage configuration | `dev-ws-storage` |
| 8 | Databricks account console | Workspace | `DEV`* |
| 9 | Databricks account console | Unity Catalog metastore + assignment | `dbks-infra-meta-us2` |
| 10 | Workspace SQL editor | Catalog + schemas + workspace binding | `dbks-infra-dev-cat`† |
| 11 | Databricks account console | Service principals + groups | `dbks-infra-dev-sp-*`, `dbks-infra-dev-grp-*` |

\* The workspace naming field only accepts a display name — `DEV` is what
was actually typed, which also matches the `DEV`/`PROD` pattern in
`docs/naming-conventions.docx` (this project name column elsewhere follows
the AWS-resource pattern, but the live workspace itself is named per that
separate Databricks convention). See Appendix A.

† This is the prescriptive step. The live `DEV` workspace never actually had
this step run — its catalog is Unity Catalog's auto-generated default
(`dev_<workspace_id>`), and the `raw/bronze/silver/gold/stage` schemas below
were never created. See Appendix A and Jira IT-66 for the follow-up to
create a real project-named catalog.

---

# Part 1 — AWS networking

You'll build the customer-managed VPC Databricks will run inside.

### Step 1.1 — Create the VPC

Open the AWS console → **VPC** service → **Your VPCs** → **Create VPC**. Pick
"VPC only" and fill in the values from **Table 1.1**.

**Table 1.1 — VPC**

| Field | Value |
|---|---|
| Name tag | `dbks-infra-dev-vpc` |
| IPv4 CIDR | `10.0.0.0/16` |
| Tenancy | Default |

After creation, select the new VPC → **Actions** → **Edit VPC settings** and
turn on:

- DNS hostnames (**required** by Databricks)
- DNS resolution (**required** by Databricks)

### Step 1.2 — Create the three subnets

In **VPC** → **Subnets** → **Create subnet**, choose `dbks-infra-dev-vpc` and
add the subnets one by one with the values from **Table 1.2**.

**Table 1.2 — Subnets**

| Name | CIDR | AZ | Type | Notes |
|---|---|---|---|---|
| `dbks-infra-dev-public-subnet` | `10.0.0.0/24` | `us-east-2a` | Public | Hosts the NAT Gateway |
| `dbks-infra-dev-private-subnet` | `10.0.1.0/24` | `us-east-2b` | Private | Databricks cluster nodes |
| `dbks-infra-dev-private-subnet-2` | `10.0.2.0/24` | `us-east-2a` | Private | Databricks cluster nodes |

Why three? Databricks requires **at least two private subnets in different
AZs**, and one public subnet is needed to host the NAT Gateway.

> Sizing: each cluster node uses **2 IPs** (one for management, one for Spark).
> A `/24` (256 IPs) supports ~125 concurrent nodes. Allowed netmask range per
> Databricks: `/17` to `/26`.

### Step 1.3 — Create the Internet Gateway

**VPC** → **Internet gateways** → **Create internet gateway** → name it
`dbks-infra-dev-IGW` → **Actions** → **Attach to VPC** → pick `dbks-infra-dev-vpc`.

### Step 1.4 — Allocate an Elastic IP and create the NAT Gateway

1. **VPC** → **Elastic IPs** → **Allocate Elastic IP address** (no name needed
   — this becomes the NAT GW public IP).
2. **VPC** → **NAT gateways** → **Create NAT gateway** with the values from
   **Table 1.4**.

**Table 1.4 — NAT Gateway**

| Field | Value |
|---|---|
| Name | `dbks-infra-dev-NATG` |
| Subnet | `dbks-infra-dev-public-subnet` |
| Connectivity type | Public |
| Elastic IP allocation ID | the EIP from step 1 |

Once it goes to **Available**, note the **primary private IPv4** (e.g.
`10.0.0.79`) and **public IPv4** (e.g. `16.59.107.134`). These are the IPs your
private subnets will egress through.

> We use **one** NAT Gateway in dev to keep cost down. For prod, plan one NAT
> per AZ.

### Step 1.5 — Create the route tables

**VPC** → **Route tables** → **Create route table** twice with the names from
**Table 1.5**.

**Table 1.5 — Route tables**

| Route table | Associated subnets | Routes |
|---|---|---|
| `dbks-infra-dev-public-rt` | `dbks-infra-dev-public-subnet` | `10.0.0.0/16` → local; `0.0.0.0/0` → `dbks-infra-dev-IGW` |
| `dbks-infra-dev-private-rt` | `dbks-infra-dev-private-subnet`, `dbks-infra-dev-private-subnet-2` | `10.0.0.0/16` → local; `0.0.0.0/0` → `dbks-infra-dev-NATG` |

For each one: **Routes** tab → **Edit routes** → add the rows above.
**Subnet associations** tab → **Edit subnet associations** → tick the listed
subnets.

### Step 1.6 — Configure the Network ACL

**VPC** → **Network ACLs** → select the **Main** NACL of `dbks-infra-dev-vpc`.
Make sure all three subnets are associated (Subnet associations tab).

**Inbound rules** (Edit inbound rules):

**Table 1.6a — NACL inbound**

| Rule # | Type | Protocol | Port | Source | Action |
|---|---|---|---|---|---|
| 99 | All traffic | All | All | `0.0.0.0/0` | Allow |
| * | All traffic | All | All | `0.0.0.0/0` | Deny |

> Databricks recommends "allow all inbound" at the NACL layer and controlling
> egress at the firewall/proxy layer instead.

**Outbound rules** (Edit outbound rules):

**Table 1.6b — NACL outbound (Databricks-required ports)**

| Rule # | Type | Protocol | Port | Destination | Action | Why |
|---|---|---|---|---|---|---|
| 99  | All       | All | All  | `10.0.0.0/16` | Allow | Intra-VPC |
| 100 | HTTPS     | TCP | 443  | `0.0.0.0/0` | Allow | Databricks control plane, S3, STS, libraries |
| 101 | MySQL     | TCP | 3306 | `0.0.0.0/0` | Allow | Hive metastore (legacy — required by default) |
| 102 | HTTPS*    | TCP | 8443 | `0.0.0.0/0` | Allow | Databricks SCC — control plane API |
| 103 | Custom TCP| TCP | 8445 | `0.0.0.0/0` | Allow | Databricks SCC — control plane API |
| 104 | Custom TCP| TCP | 8444 | `0.0.0.0/0` | Allow | Unity Catalog logging + lineage |
| *   | All       | All | All  | `0.0.0.0/0` | Deny  | Default deny |

> The lower the rule number, the higher the priority. Keep the Databricks ports
> in the 99–104 range so a future "tightening" pass cannot bury them under a
> deny rule.

**Table 1.6c — Conditional outbound rules (skip unless the feature is on)**

| Port | Add only if you turn on |
|---|---|
| 53 | Custom DNS (we use `AmazonProvidedDNS`, so skip) |
| 6666 | AWS PrivateLink (not in dev scope) |
| 5432 | Lakebase (not in scope) |
| 2443 | Compliance security profile / FIPS (not in scope) |
| 8446–8451 | Reserved by Databricks for future use — add when tightening for prod |

### Step 1.7 — Create the workspace security group

**EC2** → **Security groups** → **Create security group**, named
`dbks-infra-dev-sg-workspace` (per `docs/naming-conventions.docx`), attached
to `dbks-infra-dev-vpc`.

> **This name field was missing from earlier revisions of this guide,**
> which is how the live `DEV` workspace ended up wired to the VPC's
> unnamed default security group instead — see Appendix A and Jira IT-65.

**Inbound rules** — both rules use the same SG as their source (self-reference):

**Table 1.7a — SG inbound**

| Type | Protocol | Port range | Source |
|---|---|---|---|
| All TCP | TCP | 0–65535 | this security group (self) |
| All UDP | UDP | 0–65535 | this security group (self) |

**Outbound rules**:

**Table 1.7b — SG outbound**

| Type | Protocol | Port | Destination | Why |
|---|---|---|---|---|
| All TCP | TCP | 0–65535 | this security group (self) | Internal cluster traffic |
| All UDP | UDP | 0–65535 | this security group (self) | Internal cluster traffic |
| HTTPS   | TCP | 443  | `0.0.0.0/0` | Control plane, S3, STS |
| MySQL   | TCP | 3306 | `0.0.0.0/0` | Hive metastore |
| Custom TCP | TCP | 8443 | `0.0.0.0/0` | SCC |
| Custom TCP | TCP | 8444 | `0.0.0.0/0` | Lineage / logging |
| Custom TCP | TCP | 8445 | `0.0.0.0/0` | SCC |

Note its **Group ID** — you'll paste it into the Databricks network config
(Step 6).

### Step 1.8 — DHCP option set (verify, no action required)

**VPC** → **DHCP option sets**. The default `dbks-infra-dev-DHCP-option-set`
should already have:

- Domain name: `us-east-2.compute.internal`
- Domain name servers: `AmazonProvidedDNS`

If a custom one was created during the manual deploy, confirm those two values
match. Databricks needs DNS resolution working.

### Smoke-test the network

Before moving on, confirm the egress path:

```
EC2 (private subnet) → dbks-infra-dev-private-rt
                     → dbks-infra-dev-NATG (10.0.0.79 → 16.59.107.134)
                     → dbks-infra-dev-public-rt
                     → dbks-infra-dev-IGW
                     → Internet (control plane / S3 / STS)
```

Easiest check: launch a temporary `t3.micro` in `dbks-infra-dev-private-subnet`
with no public IP, attach the workspace SG, and from Session Manager run
`curl -v https://sts.amazonaws.com`. If you get a TLS handshake, the path
works. Terminate the instance before continuing.

---

# Part 2 — AWS IAM cross-account credential role

Databricks needs a role in your account that it can assume from its own
production account (`414351767826`) to launch EC2 cluster nodes.

### Step 2.1 — Grab your Databricks account ID

Open <https://accounts.cloud.databricks.com> → top-right user menu → click your
email → **Account ID** is shown. Copy it. You'll use it as the `ExternalId` in
the trust policy below.

### Step 2.2 — Create the IAM role

**IAM** → **Roles** → **Create role** → **Custom trust policy** → paste
**Table 2.2a** (replace `<DATABRICKS_ACCOUNT_ID>` with the value from 2.1).
Skip "Add permissions" for now (we'll attach an inline policy on the next
screen). Name the role per **Table 2.2b**.

**Table 2.2a — Trust policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::414351767826:root" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "<DATABRICKS_ACCOUNT_ID>" }
    }
  }]
}
```

**Table 2.2b — Role**

| Field | Value |
|---|---|
| Role name | `dbks-infra-dev-ws-role` |
| Description | "Databricks cross-account compute role for `dbks-infra-dev-ws`" |

### Step 2.3 — Attach the inline policy

Open the new role → **Permissions** → **Add permissions** → **Create inline
policy** → JSON tab → paste the document from **Table 2.3**. Name it
`dbks-infra-dev-ws-role-policy`.

This is the "Customer-managed VPC with default restrictions" action set
straight from the Databricks docs.

**Table 2.3 — Inline policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2ClusterLifecycle",
      "Effect": "Allow",
      "Resource": "*",
      "Action": [
        "ec2:AssociateIamInstanceProfile",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CancelSpotInstanceRequests",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteTags",
        "ec2:DeleteVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeIamInstanceProfileAssociations",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeNatGateways",
        "ec2:DescribeNetworkAcls",
        "ec2:DescribePrefixLists",
        "ec2:DescribeReservedInstancesOfferings",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotInstanceRequests",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcAttribute",
        "ec2:DescribeVpcs",
        "ec2:DetachVolume",
        "ec2:DisassociateIamInstanceProfile",
        "ec2:ReplaceIamInstanceProfileAssociation",
        "ec2:RequestSpotInstances",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeFleetHistory",
        "ec2:ModifyFleet",
        "ec2:DeleteFleets",
        "ec2:DescribeFleetInstances",
        "ec2:DescribeFleets",
        "ec2:CreateFleet",
        "ec2:DeleteLaunchTemplate",
        "ec2:GetLaunchTemplateData",
        "ec2:CreateLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:ModifyLaunchTemplate",
        "ec2:DeleteLaunchTemplateVersions",
        "ec2:CreateLaunchTemplateVersion",
        "ec2:AssignPrivateIpAddresses",
        "ec2:GetSpotPlacementScores"
      ]
    },
    {
      "Sid": "SpotServiceLinkedRole",
      "Effect": "Allow",
      "Action": ["iam:CreateServiceLinkedRole", "iam:PutRolePolicy"],
      "Resource": "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot",
      "Condition": {
        "StringLike": { "iam:AWSServiceName": "spot.amazonaws.com" }
      }
    }
  ]
}
```

### Step 2.4 — Copy the role ARN

Open the role → copy its **ARN** (looks like
`arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-dev-ws-role`). You'll paste it
into Databricks in Step 5.

---

# Part 3 — Workspace S3 bucket

This bucket holds workspace artifacts (notebooks, init scripts, system tables
data, etc.) **and** Unity Catalog managed data under `/unity-catalog/*`. The
metastore is provisioned with no `storage_root` (see Part 9), so there is no
separate metastore bucket — UC managed data lands in this same bucket.

### Step 3.1 — Create the bucket

**S3** → **Create bucket** with the values in **Table 3.1**.

**Table 3.1 — Bucket settings**

| Setting | Value |
|---|---|
| Bucket name | `dbks-infra-dev-s3-ws` |
| Region | `us-east-2` |
| Object Ownership | Bucket owner enforced (ACLs disabled) |
| Block Public Access | **All four toggles ON** |
| Bucket versioning | Enable |
| Default encryption | SSE-KMS, with the project CMK |

### Step 3.2 — Apply the bucket policy

Open the bucket → **Permissions** tab → **Bucket policy** → **Edit** → paste
**Table 3.2** (replace `<DATABRICKS_ACCOUNT_ID>` with the value from 2.1).

**Table 3.2 — Bucket policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GrantDatabricksAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::414351767826:root" },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::dbks-infra-dev-s3-ws",
        "arn:aws:s3:::dbks-infra-dev-s3-ws/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/DatabricksAccountId": ["<DATABRICKS_ACCOUNT_ID>"]
        }
      }
    },
    {
      "Sid": "PreventDBFSAccessToUnityCatalogPaths",
      "Effect": "Deny",
      "Principal": { "AWS": "arn:aws:iam::414351767826:root" },
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::dbks-infra-dev-s3-ws/unity-catalog/*"]
    }
  ]
}
```

> The **Deny** statement is mandatory for UC-enabled workspaces. It stops the
> legacy DBFS layer from reaching anything under `unity-catalog/*`.

---

# Part 4 — AWS IAM storage trust role (self-assuming)

This role lets Databricks's Unity Catalog `UCMasterRole` read/write the
workspace bucket on your behalf. It must trust **both** the UCMasterRole **and
itself** — the "self-assume" pattern is the part most people miss the first
time.

You'll do this in **two passes** because the role has to exist before its own
ARN can appear in the trust policy.

### Step 4.1 — First pass: create the role with the initial trust

**IAM** → **Roles** → **Create role** → **Custom trust policy** → paste
**Table 4.1a**. Skip permissions on this screen, then name the role per
**Table 4.1b**.

**Table 4.1a — Initial trust policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
    },
    "Action": "sts:AssumeRole",
    "Condition": { "StringEquals": { "sts:ExternalId": "0000" } }
  }]
}
```

**Table 4.1b — Role**

| Field | Value |
|---|---|
| Role name | `dbks-dev-trust-role-ws` |
| Description | "Databricks workspace storage + UC trust role" |

### Step 4.2 — Attach the access policy

Open the role → **Add permissions** → **Create inline policy** → JSON tab →
paste **Table 4.2** (replace `<AWS_ACCOUNT_ID>` and `<CMK_ID>`). Name it
`dbks-dev-trust-role-ws-policy`.

**Table 4.2 — Storage access policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadWriteUCPath",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::dbks-infra-dev-s3-ws/unity-catalog/*"
    },
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::dbks-infra-dev-s3-ws"
    },
    {
      "Sid": "KMSDataKeys",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"],
      "Resource": ["arn:aws:kms:us-east-2:<AWS_ACCOUNT_ID>:key/<CMK_ID>"]
    },
    {
      "Sid": "SelfAssume",
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": ["arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-dev-trust-role-ws"]
    }
  ]
}
```

### Step 4.3 — Second pass: update the trust to self-assume

Copy the role's **ARN** (you'll need it). Then **Trust relationships** tab →
**Edit trust policy** → replace the JSON with **Table 4.3** (replace
`<DATABRICKS_ACCOUNT_ID>` and `<AWS_ACCOUNT_ID>`).

**Table 4.3 — Final trust policy (self-assuming)**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": [
        "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
        "arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-dev-trust-role-ws"
      ]
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "<DATABRICKS_ACCOUNT_ID>" }
    }
  }]
}
```

> If you skip Step 4.3, UC jobs that re-assume the storage role will fail
> with `AccessDenied`. This is the single most common mistake.

### Step 4.4 — (Optional) Add the file-events policy

If you plan to use Auto Loader / file-event notifications, attach the
"file events" inline policy from the
[Databricks docs](https://docs.databricks.com/aws/en/admin/workspace/create-uc-workspace?language=Customer-managed%C2%A0VPC%C2%A0with%C2%A0default%C2%A0restrictions#credential)
(grants S3 bucket-notification + SNS + SQS lifecycle). Skip if you don't need
it yet.

---

# Part 5 — Databricks credential configuration

Now you switch to the **Databricks account console** at
<https://accounts.cloud.databricks.com>. The first thing you'll do here is
register the IAM role from Part 2.

### Step 5.1 — Open the workspace creation flow

**Workspaces** in the left nav → **Create workspace**. The form has three
dropdowns at the top: Compute credentials, Network configuration, Workspace
storage. You'll fill them in this order: 5 → 6 → 7.

### Step 5.2 — Add the cloud credential

In the **Compute credentials** dropdown → **Add cloud credential** → **Add
manually**. Fill in **Table 5.2**.

**Table 5.2 — Credential configuration**

| Field | Value |
|---|---|
| Credential configuration name | `dev-ws-cloud-credential` |
| Cross-account IAM role ARN | the ARN you copied in Step 2.4 |

Click **Save**. Databricks runs a quick validation; if it fails, double-check
the trust policy uses your account ID as the `ExternalId`.

---

# Part 6 — Databricks network configuration

Still on the create-workspace form. In the **Network configuration** dropdown →
**Add network configuration**.

### Step 6.1 — Fill in the VPC details

**Table 6.1 — Network configuration**

| Field | Value |
|---|---|
| Network configuration name | `dbks-infra-dev-network-config` |
| VPC ID | `vpc-...` of `dbks-infra-dev-vpc` (from Step 1.1) |
| Subnet IDs | the IDs of `dbks-infra-dev-private-subnet` and `dbks-infra-dev-private-subnet-2` (from Step 1.2) |
| Security group IDs | the ID of the workspace SG (from Step 1.7) |

> Pass **only the two private subnets**. The public subnet stays out — it's
> for the NAT GW, not Databricks.

Click **Save**. If validation fails on subnets, the most common cause is
specifying two subnets in the same AZ.

---

# Part 7 — Databricks storage configuration

Same form. In the **Workspace storage** dropdown → **Add new cloud storage** →
**Add manually**.

### Step 7.1 — Wire the bucket to the trust role

**Table 7.1 — Storage configuration**

| Field | Value |
|---|---|
| Storage configuration name | `dev-ws-storage` |
| S3 bucket name | `dbks-infra-dev-s3-ws` |
| Storage IAM role ARN | the ARN of `dbks-dev-trust-role-ws` (from Step 4.3) |

Click **Save**. Validation will fail if you skipped the self-assume update in
Step 4.3 — go back and fix it.

---

# Part 8 — Create the workspace

Back on the create-workspace form, all three dropdowns now have your saved
configurations selected. Fill in the rest.

### Step 8.1 — Submit the workspace

**Table 8.1 — Workspace**

| Field | Value |
|---|---|
| Workspace name | `DEV` |
| Region | `us-east-2` |
| Pricing tier | Premium (required for Unity Catalog) |
| Compute credentials | `dev-ws-cloud-credential` |
| Network configuration | `dbks-infra-dev-network-config` |
| Workspace storage | `dev-ws-storage` |

> The Databricks workspace name field follows the `DEV`/`PROD` convention in
> `docs/naming-conventions.docx`, not the `dbks-infra-{env}-*` pattern used
> for AWS resources and other Databricks object types.

Click **Save** and watch the status. It moves **Provisioning → Running**
(usually under 10 minutes). If it ends up **Failed**, click into the workspace
to see the reason — almost always one of: missing NACL outbound port, IAM
trust mismatch, S3 bucket policy missing the `Deny` on `unity-catalog/*`, or
non-self-assuming storage role.

### Step 8.2 — Note the deployment URL

Once Running, copy the workspace URL (looks like
`https://dbc-XXXXXXXX-XXXX.cloud.databricks.com`). For this manual deploy it
is `https://dbc-03363fa1-0d7a.cloud.databricks.com`. New TF deploys will get a
new deployment name — never hardcode this string downstream.

---

# Part 9 — Unity Catalog metastore + assignment

If a metastore already exists in `us-east-2` for your account, Databricks
auto-assigns it to the new workspace and you can skip to Part 10.

### Step 9.1 — Create the metastore (only if none exists in us-east-2)

In the Databricks account console: **Catalog** → **Create metastore**. Fill in
**Table 9.1**.

**Table 9.1 — Metastore**

| Field | Value |
|---|---|
| Name | `dbks-infra-meta-us2` |
| Region | `us-east-2` |
| `storage_root` | leave **blank** — not configured (project decision) |
| Storage credential | `dbks-dev-trust-role-ws` (the role from Part 4) |

> No `storage_root` means the metastore has no bucket of its own. Unity
> Catalog managed data instead lands in each workspace's own bucket
> (`dbks-infra-{env}-s3-ws`) under `/unity-catalog/*`, via the storage
> credential's access to that path (Table 4.2) and the workspace bucket's
> own `Deny` on DBFS access to that prefix (Table 3.2). There is no
> separate metastore bucket to create.

### Step 9.2 — Assign the metastore to the workspace

Same screen → select the new metastore → **Assign to workspaces** →
`DEV`.

---

# Part 10 — Catalog, schemas, workspace binding

Open the workspace itself (the URL from Step 8.2) and switch to the **SQL
editor**.

> **This step was never actually run for the live `DEV` workspace.** Its
> catalog is Unity Catalog's auto-generated default (`dev_<workspace_id>`,
> confirmed via the account API during the Terraform import — see Jira
> IT-63), with no medallion schemas created. This section remains the
> prescriptive procedure for creating a real project-named catalog per
> `docs/naming-conventions.docx`; see Jira IT-66 for that follow-up.

### Step 10.1 — Create the catalog

```sql
CREATE CATALOG IF NOT EXISTS `dbks-infra-dev-cat`;
```

### Step 10.2 — Bind the catalog to the workspace

In the workspace UI: **Catalog** → select `dbks-infra-dev-cat` → **Workspaces**
tab → **Manage** → switch from "All workspaces" to **Specific workspaces** →
add `DEV`.

### Step 10.3 — Create the schemas

```sql
USE CATALOG `dbks-infra-dev-cat`;
CREATE SCHEMA IF NOT EXISTS raw    COMMENT 'Raw data landed as-is from sources';
CREATE SCHEMA IF NOT EXISTS bronze COMMENT 'Ingested, minimally transformed';
CREATE SCHEMA IF NOT EXISTS silver COMMENT 'Cleaned, conformed, enriched';
CREATE SCHEMA IF NOT EXISTS gold   COMMENT 'Aggregated, business-ready';
CREATE SCHEMA IF NOT EXISTS stage  COMMENT 'Temporary processing area';
```

Reference styles you'll use day-to-day:

- Same workspace: `` `dbks-infra-dev-cat`.silver.fact_sells ``
- Cross-workspace (exceptional): `` DEV.`dbks-infra-dev-cat`.silver.fact_sells ``

---

# Part 11 — Identities

In the **account console** → **User management** → **Service principals** /
**Groups**.

### Step 11.1 — Service principals

Create the two service principals from **Table 11.1**, then add each to the
workspace (**Workspaces → DEV → Permissions → Add**).

**Table 11.1 — Service principals**

| Name | Purpose |
|---|---|
| `dbks-infra-dev-sp-deploy` | CI/CD deploys (GitHub Actions assumes this via OIDC) |
| `dbks-infra-dev-sp-etl` | Scheduled ETL job runner |

### Step 11.2 — Groups

Create the two groups from **Table 11.2**, add the appropriate humans, and
grant them workspace + catalog permissions as needed.

**Table 11.2 — Groups**

| Name | Members | Typical grants |
|---|---|---|
| `dbks-infra-dev-grp-data-engineers` | DEs | `USE CATALOG`, `CREATE SCHEMA`, full DML on all schemas |
| `dbks-infra-dev-grp-analysts` | Analysts | `USE CATALOG`, `SELECT` on `silver` + `gold` |

> When the prod workspace is mounted later, repeat Part 11 with the
> `dbks-infra-prod-*` names.

---

# Part 12 — Verification

Before declaring the workspace done, run through these checks.

| Check | How |
|---|---|
| Workspace status is **Running** | Account console → Workspaces |
| You can log into the workspace | Open the URL from Step 8.2 |
| Cluster starts and stays running | Compute → Create cluster (smallest single-node config); wait for green |
| `SELECT 1` works on the cluster | SQL editor against the cluster |
| Catalog is bound | Catalog → live catalog name (see Appendix A) → Workspaces tab shows `DEV` only |
| Write a managed table to UC | `CREATE TABLE <catalog>.default.smoke_test (id INT) USING DELTA;` then `DROP TABLE` (substitute the live catalog/schema from Appendix A — `dbks-infra-dev-cat` and the `stage` schema in this row's original form don't exist; see IT-66) |
| No DBFS path can hit `unity-catalog/*` | `dbutils.fs.ls("s3://dbks-infra-dev-s3-ws/unity-catalog/")` should error (Deny in Table 3.2) |

If any of those fail, walk back to the section listed in **Appendix C**.

---

# Appendix A — Resource name reference

| Layer | Resource | Name |
|---|---|---|
| VPC | VPC | `dbks-infra-dev-vpc` |
| VPC | Public subnet | `dbks-infra-dev-public-subnet` |
| VPC | Private subnet 1 | `dbks-infra-dev-private-subnet` |
| VPC | Private subnet 2 | `dbks-infra-dev-private-subnet-2` |
| VPC | Public route table | `dbks-infra-dev-public-rt` |
| VPC | Private route table | `dbks-infra-dev-private-rt` |
| VPC | IGW | `dbks-infra-dev-IGW` |
| VPC | NAT GW | `dbks-infra-dev-NATG` |
| VPC | DHCP option set | `dbks-infra-dev-DHCP-option-set` |
| IAM | Cross-account credential role | `dbks-infra-dev-ws-role` |
| IAM | Storage trust role (self-assuming) | `dbks-dev-trust-role-ws` |
| S3 | TF state | `dbks-infra-s3-tf-state` |
| S3 | Workspace artifacts | `dbks-infra-dev-s3-ws` |
| S3 | UC managed data (dev) | `dbks-infra-dev-s3-ws/unity-catalog/*` (no separate metastore bucket — metastore has no `storage_root`) |
| Databricks | Credential config | `dev-ws-cloud-credential` |
| Databricks | Network config | `dbks-infra-dev-network-config` |
| Databricks | Storage config | `dev-ws-storage` |
| Databricks | Workspace | `DEV` (`dbc-03363fa1-0d7a`) |
| Databricks | Metastore | `dbks-infra-meta-us2` |
| Databricks | Catalog (dev) | `dev_7474644050018837` |

> **Naming drift confirmed live during the Terraform import (IT-62/IT-63),
> not this manual guide's original prescription:**
> - **Workspace** — the guide's Part 5/8 steps above now say `DEV` (fixed);
>   this actually matches `docs/naming-conventions.docx`'s `DEV`/`PROD`
>   workspace pattern, so no further action needed there.
> - **Network config security group** — the live network config
>   (`dbks-infra-dev-network-config`) references the VPC's *default*
>   security group, not the dedicated `dbks-infra-dev-sg-workspace` this
>   guide's Part 1/6 steps call for. Tracked in Jira IT-65.
> - **Catalog** — no `dbks-infra-dev-cat` was ever created; the live
>   catalog is Unity Catalog's auto-generated default
>   (`dev_<workspace_id>`), and only the `default`/`information_schema`
>   schemas exist (not the `raw/bronze/silver/gold/stage` medallion set
>   this guide's Part 10 describes). Tracked in Jira IT-66.

---

# Appendix B — Issues encountered (fill as you go)

If you hit something the guide doesn't cover, log it here so the next person
doesn't repeat the pain.

| # | Symptom | Root cause | Fix | Section to update |
|---|---|---|---|---|
| 1 | _TBD_ | _TBD_ | _TBD_ | — |

Common gotchas you should already know about:

- **Cluster fails to start** → check NACL outbound 443 / 3306 / 8443 / 8444 / 8445 (Table 1.6b).
- **Workspace creation fails on storage validation** → storage trust role isn't self-assuming (re-do Step 4.3).
- **`AccessDenied` from a UC job hitting S3** → bucket policy missing the `aws:PrincipalTag/DatabricksAccountId` condition (Step 3.2) or storage role missing the `kms:Decrypt` action (Table 4.2).
- **DBFS reading from `unity-catalog/*`** → bucket-policy `Deny` is missing (Step 3.2).
- **NAT cost surprise** → expected with single NAT in `us-east-2a`. For prod, add one NAT per AZ.

---

# Appendix C — Recommendations for the Terraform iteration

These are notes for whoever picks up the Terraform implementation — they
mirror the structure of this manual guide.

1. **One module per part of this guide:** `modules/network`,
   `modules/iam-credential`, `modules/s3-workspace`, `modules/iam-storage`,
   `modules/databricks-workspace`. Top-level `envs/dev` and `envs/prod`
   compose them.
2. **Self-assuming storage role** (Step 4.3) requires a two-pass apply in
   Terraform. Either use a `null_resource` that updates `aws_iam_role.assume_role_policy`
   after the role exists, or use a `data "aws_iam_policy_document"` that
   references `aws_iam_role.this.arn` and updates on the second `apply`.
3. **NACL discipline** — codify outbound rules 100–104 (Table 1.6b) as a
   `for_each` map keyed by purpose so removing a Databricks-required port is
   obvious in the diff. Reserve `105–110` for Table 1.6c ports when they
   become needed.
4. **Constants in one place** — Databricks production account `414351767826`
   and the `UCMasterRole` ARN should be `locals` in a single `databricks.tf`,
   never copy-pasted across modules.
5. **Variables, not literals** — `vpc_cidr`, `private_subnet_cidrs`,
   `public_subnet_cidrs`, `azs`, `region` are all variables. Don't hardcode
   `10.0.0.0/16` or `us-east-2`.
6. **Add VPC endpoints** (not in the manual deployment): Gateway for S3 +
   DynamoDB; Interface for STS, Kinesis, Secrets Manager, KMS. Cuts NAT cost
   and keeps secret retrieval off the public path.
7. **NAT count** — single NAT for dev (parameterize as `nat_gateway_count = 1`),
   one NAT per AZ for prod.
8. **State + locking** — keep `dbks-infra-s3-tf-state` (default SSE-S3, no
   KMS, per project decision); add a DynamoDB lock table on-demand.
9. **Secrets** — `databricks_account_id`, account-level client secret,
   workspace PATs all live in Secrets Manager (`dbks-infra-{env}-sm-*`) with
   CMK encryption + 90-day rotation. Read at runtime via
   `data "aws_secretsmanager_secret_version"`.
10. **ExternalId condition** — keep it on every role trusted by
    `arn:aws:iam::414351767826:root`. It's required by Databricks; don't
    regress.
11. **Workspace deployment name** — `dbc-03363fa1-0d7a` is the manual one.
    Terraform will produce a different one — downstream code must use
    `databricks_mws_workspaces.this.workspace_url`, never a hardcoded string.
