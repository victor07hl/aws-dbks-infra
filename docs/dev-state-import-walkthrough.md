# Dev State Import — Walkthrough & History

How the already-deployed **dev** AWS environment was adopted into Terraform
state (a *brownfield import*), end to end. Written as a reference so the same
process can be repeated for **prod** and understood by the next engineer.

> Scope of this import: AWS only — network + IAM + S3 (25 resources).
> Databricks resources (workspace, catalog, metastore) were intentionally out
> of scope (they need the Databricks provider auth configured separately).

---

## The big picture: what problem this solved

The dev AWS resources were **built by hand** (see `manual-deployment-findings.md`).
Terraform knew nothing about them. A brownfield import makes Terraform "adopt"
existing resources into its state *without recreating them*, and produces `.tf`
config that matches what is live.

Three things must line up:

```
   Real AWS resources   <->   Terraform STATE   <->   Terraform CONFIG (.tf)
   (live infra)               (what TF tracks)         (what you wrote)
```

A normal `apply` makes infra match config. **Import** instead binds an existing
real resource into state, then you write config to match it. When all three
agree, `plan` reports **"No changes."**

---

## Part 1 — Authentication foundation (the SSO chain)

Terraform's AWS provider needs credentials. This project uses **no static keys** —
it uses AWS IAM Identity Center (SSO) + role assumption, configured in
`~/.aws/config` as a **two-profile chain**:

```ini
[sso-session dbks-sso]
sso_start_url = https://d-9a675b7b7b.awsapps.com/start
sso_region    = us-east-2

[profile dbks-sso]              # SSO entry point (who you are)
sso_session    = dbks-sso
sso_account_id = 252231277941
sso_role_name  = dbks-infra-ps-tf-local

[profile dbks-tf]              # what Terraform uses (what you can do)
source_profile    = dbks-sso          # get SSO creds from dbks-sso...
role_arn          = arn:aws:iam::252231277941:role/dbks-infra-iam-role-tf-local  # ...then assume this
role_session_name = victor.moreno-tf-local
region            = us-east-2
```

**Why two profiles?** Putting `sso_session` and `role_arn` in the same block
fails with `Partial credentials found in assume-role`. The CLI needs them split:
`dbks-sso` logs you in; `dbks-tf` uses those creds to **assume the deploy role**.
`source_profile = dbks-sso` is the bridge.

Auth flow:

```
aws sso login --profile dbks-sso       -> browser login, short-lived SSO token
  -> SSO role: AWSReservedSSO_dbks-infra-ps-tf-local_...
    -> assumes dbks-infra-iam-role-tf-local   (the role with real permissions)
      -> Terraform runs as that role
```

**Validate auth:**

```bash
aws sso login --profile dbks-sso                 # refresh the token
aws sts get-caller-identity --profile dbks-tf    # must show .../dbks-infra-iam-role-tf-local/...
export AWS_PROFILE=dbks-tf                        # Terraform picks this up
```

### Gotchas hit (and fixes)

- **`dbks-tf` had `sso_session` + `role_arn` in one block** -> rewrote as the
  two-profile chain above.
- **Permission set `dbks-infra-ps-tf-local` change not provisioned** -> the
  `sts:AssumeRole` grant must be pushed to the account: IAM Identity Center ->
  AWS accounts -> Reprovision.
- **Trust policy on `dbks-infra-iam-role-tf-local` rejected the SSO principal**
  -> simplified the role trust to the account root (the SSO permission set's
  inline policy does the gating):

  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::252231277941:root" },
      "Action": "sts:AssumeRole"
    }]
  }
  ```

---

## Part 2 — Discovery: reading live AWS state with the CLI

Before importing, find each resource's **real ID** and **actual attributes** so
the config matches reality. Pure AWS CLI (read-only), not Terraform:

```bash
# Network
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=dbks-infra-dev-vpc"
aws ec2 describe-subnets --filters "Name=tag:Name,Values=dbks-infra-dev-*"
aws ec2 describe-internet-gateways
aws ec2 describe-nat-gateways
aws ec2 describe-route-tables
aws ec2 describe-security-groups
aws ec2 describe-addresses --allocation-ids <eip>      # NAT's Elastic IP

# IAM
aws iam get-role --role-name dbks-infra-dev-ws-role
aws iam list-role-policies / get-role-policy            # inline policies
aws iam list-attached-role-policies / get-policy-version # managed policies

# S3
aws s3api get-bucket-encryption / get-bucket-versioning / get-bucket-policy
```

This is where **drift from the guide** was discovered (bucket is SSE-S3 not KMS,
versioning off, default NACL only, VPC named `dbks-infra`). Knowing reality first
is what lets the import end in "No changes."

Discovered IDs included `vpc-0c0888b82c6975777`, the three subnets, IGW, NAT,
EIP, two route tables, the security group, two IAM roles, etc.

---

## Part 3 — The import scaffolding (`import` blocks)

Terraform >= 1.5 imports declaratively. `environments/dev/imports.tf` had one
**`import` block** per resource:

```hcl
import {
  to = aws_vpc.this                 # Terraform address it will live at
  id = "vpc-0c0888b82c6975777"      # real AWS ID to bind
}

import {
  to = aws_iam_role_policy.credential
  id = "dbks-infra-dev-ws-role:dbks-dev-ws-policy"   # composite IDs vary per type
}
```

Each resource type has its own **import ID format** (look it up in the provider
docs under the resource's "Import" section). Examples used here:

| Resource | Import ID format | Example |
|---|---|---|
| `aws_vpc` | vpc id | `vpc-0c08...` |
| `aws_route_table_association` | `subnet_id/rt_id` | `subnet-04.../rtb-0e...` |
| `aws_iam_role_policy` | `role:policy_name` | `dbks-infra-dev-ws-role:dbks-dev-ws-policy` |
| `aws_iam_role_policy_attachment` | `role/policy_arn` | `dbks-dev-trust-role-ws/arn:aws:iam::...:policy/...` |
| `aws_iam_policy` | policy ARN | `arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy` |
| `aws_s3_bucket*` | bucket name | `dbks-infra-dev-s3-ws` |

Import *blocks* beat the old imperative `terraform import <addr> <id>` because
they are version-controllable and pair with config generation (Part 5).

---

## Part 4 — `terraform init`

```bash
terraform init
```

- Connects the **S3 backend** (`backend.tf`) — `envs/dev/terraform.tfstate`
- Downloads **providers** pinned in `versions.tf` (aws `~> 5.0`, databricks `~> 1.39`)
- Writes `.terraform.lock.hcl` (exact provider versions/hashes — commit this)

Always the first command in a fresh checkout or after changing backend/providers.

---

## Part 5 — Generating `generated.tf` (the key step)

`generated.tf` was **not hand-written**. Terraform wrote it:

```bash
terraform plan -generate-config-out=generated.tf
```

For every `import` block whose `to` address has **no matching config yet**,
Terraform:

1. Reads the live resource from AWS (provider `describe` calls),
2. Translates that live state into HCL,
3. Writes it to the named file.

So `generated.tf` is a machine-generated mirror of reality (hence every
attribute spelled out). `-generate-config-out` is a flag on `plan`; generation
never happens during `apply`.

---

## Part 6 — Cleaning the generator's quirks

`generate-config-out` emits a few invalid attributes; the first plans errored on
them. Fixes applied by hand:

| Generated (broken) | Fix | Why |
|---|---|---|
| `enable_lni_at_device_index = 0` | removed | provider rejects `0` |
| `map_customer_owned_ip_on_launch = false` (alone) | removed | requires companion args |
| `ipv6_netmask_length = 0` | removed | invalid without IPAM pool |
| `availability_zone` + `availability_zone_id` both set | kept one | mutually exclusive |
| `route = [{ ...empty strings... }]` | rewrote as `route { }` block | `ipv6_cidr_block = ""` fails CIDR validation |

Generated config is a *draft* you review and tidy. Re-run `terraform plan` after
each fix until it parses cleanly.

---

## Part 7 — The two-phase apply

A plain plan showed `25 to import, 0 to add, 15 to change, 0 to destroy`. The
15 "changes" were just `default_tags` (Project/Environment/ManagedBy). To keep
the **first** import a pure no-op, the work was split:

**Phase A — pure import (zero live changes):**

```bash
# default_tags temporarily commented out in providers.tf
terraform plan                  # -> 25 to import, 0 to change   (pure import)
terraform apply -auto-approve   # writes state only; touches nothing live
```

**Phase B — tags as a reviewed change:**

```bash
# default_tags re-enabled
terraform apply -auto-approve   # -> 0 to add, 15 to change (just tags)
```

Phase B surfaced an **IAM chicken-and-egg**: the deploy policy's tag condition
required `Project = "dbks-infra"` but `default_tags` sent `aws-dbks-infra`, so
tagging was denied until the live policy condition was corrected to
`aws-dbks-infra`. Lesson: tag-conditioned IAM policies can block tagging of
untagged brownfield resources.

Cleanup once state was written:

```bash
rm imports.tf     # import blocks are spent after the state is written
```

---

## Part 8 — The validation toolkit (everyday commands)

Run from `environments/dev`:

```bash
# 1. Formatting — canonical style?
terraform fmt -check -recursive      # reports files needing formatting (exit 1 if any)
terraform fmt -recursive             # fixes them

# 2. Validate — config internally valid? (syntax, types, refs) — OFFLINE, needs init
terraform validate                   # "Success! The configuration is valid."

# 3. Plan — config matches reality? (talks to AWS)
terraform plan                       # the truth-teller; want "No changes"

# 4. State inspection — what TF tracks
terraform state list                 # all managed resources (25 here)
terraform state show aws_vpc.this    # full attributes of one resource
```

What each proves:

- `fmt` -> style only (CI often gates on it)
- `validate` -> code is well-formed (offline; typos, bad refs, wrong types)
- `plan` -> code matches the live world (online; the real correctness check)
- `state list/show` -> confirms what is under management

Gold-standard "healthy import" signal:

```
terraform validate   -> Success
terraform plan       -> No changes. Your infrastructure matches the configuration.
```

Dev passes both — and the same `plan` passes in **CI** via the OIDC
`dbks-infra-iam-role-gha-deploy` role, proving it is not just working on one
machine.

---

## One-line summary of the sequence

```
fix SSO chain -> aws sts get-caller-identity (auth OK)
  -> aws ... describe/get (learn real IDs + attrs)
    -> write import blocks (imports.tf)
      -> terraform init (backend + providers)
        -> terraform plan -generate-config-out=generated.tf (TF writes config)
          -> clean generator quirks -> terraform plan (parses clean)
            -> terraform apply (Phase A: pure import, 0 changes)
              -> terraform apply (Phase B: tags)
                -> fmt / validate / plan / state list (verify)
```

---

## Supporting IAM changes made during the import

To let the deploy role read/manage the brownfield resources, the live
`dbks-infra-iam-role-tf-local` policy (and the matching
`dbks-infra-iam-role-gha-deploy` policy) were updated and consolidated to match
`terraform-setup-aws.md` **Table 2.2**:

- Broadened IAM scope to `dbks-dev-*` / `dbks-prod-*` (the UC storage trust role
  and its policies are named `dbks-{env}-*`, not `dbks-infra-*`).
- Added IAM read actions (`GetRolePolicy`, `ListRolePolicies`,
  `ListInstanceProfilesForRole`, `ListRoleTags`) needed for import/plan.
- Added `TagPolicy`/`UntagPolicy`, `CreatePolicyVersion`/`DeletePolicyVersion`,
  `DeleteRolePolicy`, `UpdateAssumeRolePolicy`.
- Fixed the `Project` tag-condition value to `aws-dbks-infra` (must equal
  `default_tags`).

---

## Known drift captured as-is (remediation deferred)

The config mirrors what is actually deployed, which diverges from the guide:

- Workspace bucket uses **SSE-S3**, not SSE-KMS CMK
- Bucket **versioning is OFF**
- **Default NACL** only — no Databricks port rules
- Security group is `launch-wizard-3` with minimal rules (fixed via IT-65 — see `manual-deployment-findings.md` Appendix A)
- VPC Name tag is `dbks-infra` (not `dbks-infra-dev-vpc`)

These are deliberate future changes, separate from the import.

## Follow-ups

- Modularize `generated.tf` into `modules/*` via `terraform state mv` (no infra change).
- Remediate the drift above as reviewed changes.
- Repeat this process for the **prod** environment.
