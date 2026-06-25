# Terraform Setup on AWS — End-to-End Guide

This guide walks you through bootstrapping Terraform on AWS for the
`aws-dbks-infra` repository. By the time you finish, you'll have remote
state in S3 (with **native S3 locking** — no DynamoDB), an IAM role for
local plan/apply, and an OIDC-federated IAM role used by GitHub Actions
for `dev` and `main` branch deploys.

The order matters: every resource depends on those built in earlier
sections. **Do not skip ahead.**

> **Authoritative references**
> - [Backend Type: S3 — `use_lockfile` (Terraform 1.10+)](https://developer.hashicorp.com/terraform/language/backend/s3#use_lockfile)
> - [Configuring OpenID Connect in AWS — GitHub Docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
> - [`aws-actions/configure-aws-credentials` action](https://github.com/aws-actions/configure-aws-credentials)
>
> **Diagrams:** `docs/architecture/aws-infrastructure.drawio` (pages
> `storage`, `iam`, `ci-cd-pipeline`).
>
> **Companion doc:** `docs/manual-deployment-findings.md` (Databricks
> workspace bring-up that *consumes* this Terraform setup).

---

## Before you start

You need:

- AWS console access in the target account, with permission to create
  S3 buckets, IAM roles, and an OIDC identity provider.
- Owner or admin access to the GitHub repository
  `victor07hl/aws-dbks-infra`.
- AWS CLI v2 installed locally.
- Terraform **`>= 1.10`** installed locally (required for native S3
  state locking).
- Your AWS account ID. You'll paste it many times.

Region for everything below: **`us-east-2`**.

### Constants

| What | Value | Where it appears |
|---|---|---|
| AWS account ID | `<AWS_ACCOUNT_ID>` | Trust policies, role ARNs, KMS keys |
| Region | `us-east-2` | Every AWS resource |
| GitHub OIDC issuer | `token.actions.githubusercontent.com` | OIDC provider URL |
| GitHub OIDC thumbprint | `6938fd4d98bab03faadb97b34396831e3780aea1` | Provider thumbprint (rotated very rarely) |
| Repo `sub` claim prefix | `repo:victor07hl/aws-dbks-infra:` | OIDC trust condition |
| Audience | `sts.amazonaws.com` | OIDC trust condition |
| State bucket | `dbks-infra-s3-tf-state` | `backend "s3"` block |

### What you'll build (deployment order)

| # | Where | What you create | Project name |
|---|---|---|---|
| 1 | AWS console | S3 bucket for Terraform state | `dbks-infra-s3-tf-state` |
| 2 | AWS console | IAM role for local Terraform plan/apply | `dbks-infra-iam-role-tf-local` |
| 3 | AWS console | IAM OIDC identity provider for GitHub | `token.actions.githubusercontent.com` |
| 4 | AWS console | IAM role for GitHub Actions deploys | `dbks-infra-iam-role-gha-deploy` |
| 5 | Local shell | AWS SSO profile + assume-role chain | `~/.aws/config` |
| 6 | GitHub repo | Workflow snippet using `configure-aws-credentials` | `.github/workflows/*.yml` |
| 7 | Repo | Terraform `backend "s3"` block with `use_lockfile = true` | `environments/{dev,prod}/backend.tf` |

> **Bootstrap note.** Steps 1–4 cannot be Terraformed because the state
> bucket and the deploy roles are *prerequisites* for any Terraform
> apply. Create them once, manually. Everything after that lives in
> Terraform code.

---

# Part 1 — Terraform state bucket (S3, no DynamoDB)

You'll create one shared bucket that backs the remote state for **all**
environments. Each env writes to a distinct key inside it.

> **Why no DynamoDB?** Terraform 1.10 introduced native state locking
> via a sibling lock object inside the same S3 bucket
> (`<key>.tflock`). It uses S3's strong consistency and conditional
> writes — no separate lock table, no extra resource to provision, no
> extra IAM surface. The DynamoDB pattern is now legacy.

### Step 1.1 — Create the bucket

**S3** → **Create bucket** with the values in **Table 1.1**.

**Table 1.1 — Bucket settings**

| Setting | Value |
|---|---|
| Bucket name | `dbks-infra-s3-tf-state` |
| Region | `us-east-2` |
| Object Ownership | Bucket owner enforced (ACLs disabled) |
| Block Public Access | **All four toggles ON** |
| Bucket versioning | **Enable** |
| Default encryption | **SSE-S3 (AES256)** — no KMS, per project decision |

> **Why SSE-S3 and not SSE-KMS?** The state bucket is touched on every
> `init/plan/apply` from both local and CI. Wrapping every state read
> in a KMS API call adds latency and IAM surface for marginal benefit
> (state files don't carry hard secrets — those live in Secrets
> Manager). Project decision: keep `dbks-infra-s3-tf-state` on default
> SSE-S3. Workspace and metastore buckets stay on SSE-KMS.

### Step 1.2 — Object lifecycle for old versions

Versioning is on so you can roll back a corrupted state. Set a
lifecycle rule to expire **noncurrent** versions after 90 days so the
bucket doesn't grow forever:

**S3** → bucket → **Management** → **Create lifecycle rule** →
"Permanently delete noncurrent versions of objects" → **90 days**.

### Step 1.3 — Bucket policy

Open the bucket → **Permissions** → **Bucket policy** → paste **Table
1.3** (replace `<AWS_ACCOUNT_ID>`).

**Table 1.3 — State bucket policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::dbks-infra-s3-tf-state",
        "arn:aws:s3:::dbks-infra-s3-tf-state/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "AllowTfRoles",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-iam-role-tf-local",
          "arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-iam-role-gha-deploy"
        ]
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::dbks-infra-s3-tf-state",
        "arn:aws:s3:::dbks-infra-s3-tf-state/*"
      ]
    }
  ]
}
```

> The role ARNs don't exist yet — that's fine if you are applying the policy via API/CLI or the console accepts the JSON.
> 
> Some AWS consoles will reject `Invalid principal in policy` until the IAM roles exist. If that happens, create the roles in Step 2 before applying this bucket policy.
> as-is and only enforces it when the principals try to access. You'll
> create the roles in Parts 2 and 4.

---

# Part 2 — IAM role for local Terraform

A developer logs in via SSO, then assumes this role to run
`terraform plan/apply` from their machine.

### Step 2.1 — Create the role

**IAM** → **Roles** → **Create role** → **Custom trust policy** →
paste **Table 2.1a** (replace `<AWS_ACCOUNT_ID>` and the SSO permission
set ARN — see the comment).

**Table 2.1a — Trust policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::<AWS_ACCOUNT_ID>:root"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringLike": {
        "aws:PrincipalArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_*"
      }
    }
  }]
}
```

> The `StringLike` condition restricts assume-role to **principals
> federated via IAM Identity Center (SSO)**. If your account doesn't
> use SSO, replace the condition value with the IAM user/group ARN
> pattern you do use. Do **not** leave the trust open to bare account
> root — that defeats the purpose.

**Table 2.1b — Role**

| Field | Value |
|---|---|
| Role name | `dbks-infra-iam-role-tf-local` |
| Description | "Terraform deploy role for local plan/apply" |
| Maximum session duration | 4 hours |

### Step 2.2 — Attach the deploy policy

Open the role → **Add permissions** → **Create inline policy** → JSON
tab → paste **Table 2.2**. Name it `dbks-infra-iam-role-tf-local-policy`.

**Table 2.2 — Terraform deploy policy (inline)**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TfStateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::dbks-infra-s3-tf-state",
        "arn:aws:s3:::dbks-infra-s3-tf-state/*"
      ]
    },
    {
      "Sid": "ProjectInfra",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "s3:*",
        "kms:*",
        "secretsmanager:*",
        "logs:*",
        "cloudtrail:*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*",
      "Condition": {
        "StringEqualsIfExists": {
          "aws:RequestTag/Project": "aws-dbks-infra",
          "aws:ResourceTag/Project": "aws-dbks-infra"
        }
      }
    },
    {
      "Sid": "ProjectIam",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListRoles",
        "iam:ListPolicies",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-*",
        "arn:aws:iam::<AWS_ACCOUNT_ID>:policy/dbks-infra-*",
        "arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/dbks-infra-*"
      ]
    },
    {
      "Sid": "ProjectIamPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "DenyDestructiveOnUnscopedResources",
      "Effect": "Deny",
      "Action": [
        "iam:DeleteUser",
        "iam:DeleteUserPolicy",
        "organizations:*",
        "account:*"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Tightening pass.** This policy now scopes IAM actions to the project prefix instead of `iam:*` on `*`.
> The `ProjectInfra` statement still uses tag-based scoping for non-IAM resources, and the `iam:PassRole` permission is restricted to `dbks-infra-*` roles and approved services.
> The `Deny` block still hard-stops anything outside Terraform's lane.

### Step 2.3 — Copy the role ARN

Open the role → copy its **ARN**. You'll paste it in Part 5.

---

# Part 3 — GitHub OIDC identity provider

GitHub's OIDC issuer mints a short-lived token for each workflow run.
AWS trusts that issuer (once configured), and exchanges the token for
temporary credentials. **No long-lived AWS keys live in GitHub.**

### Step 3.1 — Create the provider

**IAM** → **Identity providers** → **Add provider** with the values
in **Table 3.1**.

**Table 3.1 — OIDC provider**

| Field | Value |
|---|---|
| Provider type | OpenID Connect |
| Provider URL | `https://token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |
| Thumbprint | `6938fd4d98bab03faadb97b34396831e3780aea1` |

After saving, click "Get thumbprint" and confirm AWS shows the same
value above. AWS now also accepts this provider without an explicit
thumbprint (root CA validation), but providing it explicitly is still
the recommended posture.

### Step 3.2 — Note the provider ARN

It looks like
`arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`.
You'll paste it in Step 4.1.

---

# Part 4 — IAM role for GitHub Actions deploys

This is the role each workflow run will assume. Trust is restricted
to **this** repo and to specific refs (`main` for prod, `dev` for dev).

### Step 4.1 — Create the role

**IAM** → **Roles** → **Create role** → **Web identity** → choose the
provider from Step 3.1 → **Audience** = `sts.amazonaws.com`. On the
next screen, switch to **Edit trust policy** and replace the JSON with
**Table 4.1a**.

**Table 4.1a — Trust policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:victor07hl/aws-dbks-infra:ref:refs/heads/main",
          "repo:victor07hl/aws-dbks-infra:ref:refs/heads/dev",
          "repo:victor07hl/aws-dbks-infra:pull_request"
        ]
      }
    }
  }]
}
```

> **Why three subs?** `main` lets the prod apply workflow run; `dev`
> lets the dev apply workflow run; `pull_request` lets the plan-only
> workflows run on PRs. Plan-only workflows must use a **scoped-down**
> role — covered in Step 6.2.

**Table 4.1b — Role**

| Field | Value |
|---|---|
| Role name | `dbks-infra-iam-role-gha-deploy` |
| Description | "Terraform deploy role for GitHub Actions (OIDC)" |
| Maximum session duration | 1 hour |

### Step 4.2 — Attach the deploy policy

Same inline policy as **Table 2.2** in Step 2.2 (the local role).
Name it `dbks-infra-iam-role-gha-deploy-policy`.

> **Why the same policy?** Both roles do the same Terraform work.
> Splitting them into two roles (instead of one shared role) is what
> gives you separate trust surfaces — one rooted in human SSO, one
> rooted in GitHub OIDC. The actions are identical.

### Step 4.3 — Copy the role ARN

Open the role → copy its **ARN**. You'll reference it from your
GitHub workflows in Part 6.

---

# Part 5 — Local AWS authentication (SSO + assume-role)

Now you switch to your terminal. The plan: `aws sso login` gets you a
short-lived SSO token, the AWS CLI exchanges it for credentials, then
your Terraform profile assumes `dbks-infra-iam-role-tf-local` on top.

## What is IAM Identity Center and why is it necessary?

IAM Identity Center (formerly AWS SSO) is AWS's centralized identity
service. Instead of creating long-lived IAM users with permanent access
keys, Identity Center issues short-lived tokens tied to a human login
session. When a user logs in, Identity Center creates a temporary role
in the account (matching `AWSReservedSSO_<permission-set>_<suffix>`) and
the session expires automatically.

This project's trust policy in Table 2.1a uses the condition:

```json
"aws:PrincipalArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_*"
```

That pattern matches exactly those temporary SSO roles — so only a
human who logged in through Identity Center can assume
`dbks-infra-iam-role-tf-local`. No permanent access key ever touches
disk. This is the best practice the doc is designed around.

**The flow is:**
```
aws sso login
  → Identity Center issues a short-lived session
    → session role: AWSReservedSSO_dbks-infra-ps-tf-local_<suffix>
      → assumes dbks-infra-iam-role-tf-local  (trust policy matches AWSReservedSSO_*)
        → Terraform runs with that role's permissions
```

Before you can run `aws configure sso`, you need three things set up
in the AWS console. Follow Steps 5.0a through 5.0c below first.

---

### Step 5.0a — Enable IAM Identity Center

**IAM Identity Center** → **Enable** (one-click, free service).

When prompted to choose an identity source, keep the default:
**Identity Center directory**. This means users live inside AWS — no
external IdP needed for a single-developer setup.

> IAM Identity Center is regional at the management level but the
> **AWS access portal URL** is global. Enable it in `us-east-2` to
> stay consistent with the rest of this project.

Once enabled, note the **AWS access portal URL** shown on the
dashboard. It looks like `https://d-xxxxxxxxxx.awsapps.com/start`.
You will paste it in Step 5.1.

---

### Step 5.0b — Create your user

**IAM Identity Center** → **Users** → **Add user**

| Field | Value |
|---|---|
| Username | your email (e.g. `you@example.com`) |
| Email address | same |
| First / Last name | your name |

After saving, AWS sends a confirmation email. Click the link in that
email to set your password before moving on.

This user represents **you** — the developer who will run Terraform
locally.

---

### Step 5.0c — Create a permission set and assign it

A permission set is the set of IAM permissions a user gets for a
session inside a specific account. The best practice here is to keep
the permission set itself minimal: it only needs to call
`sts:AssumeRole` on the Terraform role. All actual Terraform
permissions live inside `dbks-infra-iam-role-tf-local` (Part 2).

**Why minimal?** If your SSO session were ever compromised, the attacker
could only assume one specific role. The blast radius is bounded by
the Terraform role's own policy, not by the full IAM surface of the
account.

#### Create the permission set

**IAM Identity Center** → **Permission sets** → **Create permission set**
→ **Custom permission set**

| Field | Value |
|---|---|
| Name | `dbks-infra-ps-tf-local` |
| Description | "SSO entry point for local Terraform runs" |
| Session duration | 1 hour |

Under **Inline policy**, paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AssumeLocalTfRole",
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-iam-role-tf-local"
  }]
}
```

Replace `<AWS_ACCOUNT_ID>` with your account ID.

#### Assign the user to the account

**IAM Identity Center** → **AWS accounts** → select your account →
**Assign users or groups**

- User: the user from Step 5.0b
- Permission set: `dbks-infra-ps-tf-local`

After saving, Identity Center provisions the role
`AWSReservedSSO_dbks-infra-ps-tf-local_<random-suffix>` in your
account. That is the role the trust policy wildcard in Table 2.1a
matches.

---

### Step 5.1 — Configure the SSO profile

Run `aws configure sso` and answer:

```
SSO session name: dbks-infra
SSO start URL:    https://d-xxxxxxxxxx.awsapps.com/start   ← from Step 5.0a
SSO region:       us-east-2
SSO scopes:       sso:account:access
```

Pick the AWS account and permission set (`dbks-infra-ps-tf-local`)
when prompted. Name the resulting profile `dbks-tf`.

### Step 5.2 — Add role chaining to the profile

`aws configure sso` creates the base SSO profile. Now edit
`~/.aws/config` and add the three `role_*` lines to the `dbks-tf`
profile it generated (replace `<AWS_ACCOUNT_ID>`).

**Table 5.2 — `~/.aws/config` — final `dbks-tf` profile**

```ini
[sso-session dbks-infra]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start
sso_region    = us-east-2
sso_scopes    = sso:account:access

[profile dbks-tf]
sso_session       = dbks-infra
sso_account_id    = <AWS_ACCOUNT_ID>
sso_role_name     = dbks-infra-ps-tf-local
region            = us-east-2
role_arn          = arn:aws:iam::<AWS_ACCOUNT_ID>:role/dbks-infra-iam-role-tf-local
role_session_name = ${USER}-tf-local
duration_seconds  = 3600
```

> AWS CLI v2 supports SSO + role chaining in a single profile. When
> both `sso_*` fields and `role_arn` are present, the CLI first
> authenticates via Identity Center, then assumes the specified role
> automatically. No second profile is needed.

### Step 5.3 — Verify

```bash
aws sso login --profile dbks-tf
aws sts get-caller-identity --profile dbks-tf
```

The second command should print an ARN ending in
`dbks-infra-iam-role-tf-local/<your-user>-tf-local`. If it errors with
`AccessDenied`, your SSO permission set ARN doesn't match the
`StringLike` condition from Table 2.1a — go fix the trust policy.

### Step 5.4 — Run Terraform

```bash
export AWS_PROFILE=dbks-tf
cd environments/dev
terraform init
terraform plan
```

That's it. No `AWS_ACCESS_KEY_ID` ever lives on disk.

---

# Part 6 — GitHub Actions OIDC authentication

### Step 6.1 — Add the role ARN as a repo variable

In GitHub: **Repo settings** → **Secrets and variables** → **Actions**
→ **Variables** tab → **New repository variable**:

| Field | Value |
|---|---|
| Name | `AWS_DEPLOY_ROLE_ARN` |
| Value | the ARN from Step 4.3 |

It's a **variable**, not a **secret** — the role ARN isn't sensitive
and showing it in logs makes debugging easier.

### Step 6.2 — Workflow snippet

Drop this into every Terraform workflow (`.github/workflows/*.yml`).
The `id-token: write` permission is what enables OIDC token requests.

**Table 6.2 — Workflow snippet**

```yaml
permissions:
  id-token: write   # required for OIDC
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    env:
      AWS_REGION: us-east-2
      TF_IN_AUTOMATION: "true"
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
          role-session-name: gha-${{ github.run_id }}
          aws-region: ${{ env.AWS_REGION }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.10.0

      - run: terraform init
        working-directory: environments/${{ inputs.environment }}

      - run: terraform plan -no-color
        working-directory: environments/${{ inputs.environment }}
```

> For PR (plan-only) workflows, swap in a separately-created
> read-only role (`dbks-infra-iam-role-gha-plan`) so a hostile PR
> cannot apply. Same OIDC trust as Step 4.1 but with the inline
> policy reduced to read-only actions (`*:Describe*`, `*:Get*`,
> `*:List*`, plus `s3:Get/PutObject` on the state bucket so plan can
> refresh state).

### Step 6.3 — Verify

Push a no-op change to the `dev` branch and watch the workflow run.
Look for a `Configure AWS credentials` step that prints
`Authenticated as arn:aws:sts::<AWS_ACCOUNT_ID>:assumed-role/dbks-infra-iam-role-gha-deploy/gha-<run-id>`.

If it errors with `Not authorized to perform sts:AssumeRoleWithWebIdentity`,
the most common cause is a `sub` claim mismatch — the workflow ran on
a branch you didn't list in Table 4.1a.

---

# Part 7 — Terraform backend configuration

You finally get to write Terraform. Each environment root module
points at the same bucket but a different key.

### Step 7.1 — `backend.tf` per environment

**`environments/dev/backend.tf`**

```hcl
terraform {
  backend "s3" {
    bucket       = "dbks-infra-s3-tf-state"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

**`environments/prod/backend.tf`**

```hcl
terraform {
  backend "s3" {
    bucket       = "dbks-infra-s3-tf-state"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

> **`use_lockfile = true`** is the magic — Terraform 1.10+ writes a
> sibling object `<key>.tflock` and uses an S3 conditional write
> (`If-None-Match: *`) to acquire the lock atomically. No DynamoDB.
>
> Older Terraform versions silently ignore this attribute and run
> unlocked, which is unsafe. **Pin `terraform_version` to `>= 1.10`
> in CI** (`hashicorp/setup-terraform@v3` accepts a version string).

### Step 7.2 — `versions.tf` per environment

```hcl
terraform {
  required_version = ">= 1.10"

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
}
```

### Step 7.3 — `providers.tf` per environment

```hcl
provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project     = "aws-dbks-infra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

The `Project` tag is what unlocks the wildcard permissions in the
deploy policy (Step 2.2). Don't remove it.

### Step 7.4 — First init + state migration check

From a clean checkout:

```bash
cd environments/dev
terraform init
```

Expected output ends with `Terraform has been successfully
initialized!`. If you see `Error refreshing state: AccessDenied`, the
deploy role can't read the state bucket — re-check Tables 1.3 and 2.2.

If you ever need to migrate from a local state to this backend, run
`terraform init -migrate-state` once. Skip it on greenfield envs.

---

# Part 8 — Verification

Run these end-to-end before declaring the bootstrap done.

| Check | How |
|---|---|
| State bucket exists, versioned, encrypted | S3 console → bucket → Properties |
| `dbks-infra-iam-role-tf-local` is assumable from SSO | `aws sts get-caller-identity --profile dbks-tf` |
| OIDC provider resolves | IAM → Identity providers → click the entry, confirm thumbprint |
| `dbks-infra-iam-role-gha-deploy` is assumable from a workflow | Push a no-op to `dev`, watch the workflow's "Configure AWS credentials" step |
| `terraform init` succeeds locally | `cd environments/dev && terraform init` |
| `terraform init` succeeds in CI | Same workflow run |
| Two concurrent applies are blocked | Run `terraform apply` from two terminals at the same time on the same env; the second must error with `Error acquiring the state lock` |

If any of these fail, walk back to the section listed in Appendix B.

---

# Appendix A — Resource name reference

| Layer | Resource | Name |
|---|---|---|
| S3 | TF state bucket | `dbks-infra-s3-tf-state` |
| IAM | Local Terraform role | `dbks-infra-iam-role-tf-local` |
| IAM | GitHub Actions deploy role | `dbks-infra-iam-role-gha-deploy` |
| IAM (optional) | GitHub Actions plan-only role | `dbks-infra-iam-role-gha-plan` |
| IAM | GitHub OIDC provider | `token.actions.githubusercontent.com` |
| Local | AWS CLI SSO profile | `dbks-sso` |
| Local | AWS CLI Terraform profile | `dbks-tf` |
| GitHub | Repo variable | `AWS_DEPLOY_ROLE_ARN` |
| TF | State key — dev | `envs/dev/terraform.tfstate` |
| TF | State key — prod | `envs/prod/terraform.tfstate` |
| TF | Lock object — dev | `envs/dev/terraform.tfstate.tflock` (auto, written by TF) |
| TF | Lock object — prod | `envs/prod/terraform.tfstate.tflock` (auto, written by TF) |

---

# Appendix B — Issues encountered (fill as you go)

| # | Symptom | Root cause | Fix | Section to update |
|---|---|---|---|---|
| 1 | _TBD_ | _TBD_ | _TBD_ | — |

Common gotchas:

- **`Error acquiring the state lock` from a fresh init** → previous
  apply crashed and left a stale `.tflock`. Verify nobody else is
  applying, then `terraform force-unlock <LOCK_ID>`.
- **`AccessDenied: PutObject` on the state bucket** → bucket policy
  in Table 1.3 is missing the deploy role ARN, or the role isn't
  tagged with `Project=aws-dbks-infra`.
- **`Not authorized to perform sts:AssumeRoleWithWebIdentity`** → the
  branch the workflow ran on isn't in the `sub` list in Table 4.1a.
- **Local plan works, CI plan errors with `403` on Databricks API** →
  the GHA role has no Databricks credentials. Databricks auth is a
  separate concern (see `manual-deployment-findings.md` Step 11.1 —
  use `dbks-infra-{env}-sp-deploy` and store its OAuth token in
  Secrets Manager).
- **Workflow gets credentials, then `terraform init` errors with
  `bucket not found`** → the workflow's region (`AWS_REGION`) doesn't
  match the bucket's region. Both must be `us-east-2`.
- **`use_lockfile` had no effect** → Terraform version is < 1.10. Pin
  `>= 1.10` in `setup-terraform@v3` and in `versions.tf`.

---

# Appendix C — Why this shape, and what's deliberately out of scope

- **No DynamoDB** — Terraform 1.10's S3 native locking removes the
  one reason DynamoDB was ever in this stack.
- **No KMS on the state bucket** — project decision (see CLAUDE.md
  "Storage topology"). Workspace and metastore buckets use SSE-KMS;
  state stays on SSE-S3.
- **No separate role per environment** — both dev and prod share
  `dbks-infra-iam-role-gha-deploy`. The `sub` claim list in Table
  4.1a is what gates *which branch can deploy what*, not the role
  identity. Keeping one role keeps the trust surface small.
- **No long-lived IAM users** — local devs use SSO; CI uses OIDC.
  Anywhere you see `aws_iam_user` in a future PR, push back.
- **Bootstrap is manual, not Terraformed** — chicken-and-egg. The
  state bucket and OIDC provider are created in the console once.
  Don't try to be clever and put them in a "bootstrap" Terraform
  module that uses local state — it just moves the problem.
