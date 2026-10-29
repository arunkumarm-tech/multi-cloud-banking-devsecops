# Phase 1 – AWS Foundation (detailed runbook)

**Goal:** Terraform state in S3, keyless GitHub→AWS login (OIDC, 3 roles), VPC with flow logs, security scan + plan on every PR as required checks.
**Prerequisites:** Phase 0 done; Terraform ≥ 1.14; AWS CLI logged in as `arun-devops`; Checkov.
**Account ID:** masked as `XXXXXXXXXXXX`. "Example output" = what I really got; "Expected" = not captured.

---

## Part A – Preflight

### Step 1 – Check tools and identity
```bash
cd ~/Projects/multi-cloud-banking-devsecops
git switch main && git pull
terraform version
aws --version
aws sts get-caller-identity
```
Example output:
```
Terraform v1.14.5 on darwin_arm64
aws-cli/2.33.19 Python/3.13.12 Darwin/27.0.0
"Arn": "arn:aws:iam::XXXXXXXXXXXX:user/arun-devops"
```

---

## Part B – Bootstrap buckets (`terraform/bootstrap/`)

### Step 2 – Branch
```bash
git switch -c feature/phase1-bootstrap
```

### Step 3 – Write code
Files: `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`.
What: 2 buckets with `for_each` → `mcb-tfstate-<acct>`, `mcb-backup-<acct>`. Each: versioning, AES256, public block, BucketOwnerEnforced, 90-day noncurrent expiry, TLS-only policy, `prevent_destroy`.

### Step 4 – Init, format, validate, plan
Why: `init` downloads provider · `fmt` fixes spacing only · `validate` checks syntax · `plan` compares code with real AWS.
```bash
cd terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform plan
```
Example output:
```
Plan: 14 to add, 0 to change, 0 to destroy.
  + backup_bucket = (known after apply)
  + state_bucket  = (known after apply)
```

### Step 5 – Apply
```bash
terraform apply
```
Expected: `Apply complete! Resources: 14 added`

### Step 6 – Verify buckets
```bash
STATE_BUCKET=$(terraform output -raw state_bucket)
aws s3api get-bucket-versioning --bucket "$STATE_BUCKET"
aws s3api get-public-access-block --bucket "$STATE_BUCKET"
aws s3api get-bucket-encryption --bucket "$STATE_BUCKET"
```
Example output:
```json
{ "Status": "Enabled" }
{ "PublicAccessBlockConfiguration": {
    "BlockPublicAcls": true, "IgnorePublicAcls": true,
    "BlockPublicPolicy": true, "RestrictPublicBuckets": true } }
{ "SSEAlgorithm": "AES256" }
```

### Step 7 – Move state to S3
Why: state off the laptop; S3 lockfile replaces DynamoDB; bucket name passed at init so account ID stays out of repo.
```bash
cat > backend.tf <<'TF'
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
TF
terraform init -migrate-state -backend-config="bucket=$STATE_BUCKET"
```
Answer **yes** to copy state.

### Step 8 – Verify state in S3 and clean laptop
```bash
aws s3 ls "s3://$STATE_BUCKET/bootstrap/"
terraform plan
mkdir -p ~/mcb-state-backup
mv terraform.tfstate terraform.tfstate.backup ~/mcb-state-backup/
ls
```
Example output:
```
2026-10-28 11:55:03      25592 terraform.tfstate
No changes. Your infrastructure matches the configuration.
backend.tf  main.tf  outputs.tf  variables.tf  versions.tf
```

### Step 9 – Commit, PR, merge, sync
```bash
git add versions.tf variables.tf main.tf outputs.tf backend.tf .terraform.lock.hcl
git commit -m "feat(bootstrap): S3 state and backup buckets with versioning, encryption, TLS-only and S3 lockfile"
git push -u origin feature/phase1-bootstrap
```
PR check: **Files changed** must show no `.tfstate` and no `.terraform/`.
```bash
cd ../.. && git switch main && git pull && git branch -d feature/phase1-bootstrap
```
Example output:
```
6 files changed, 182 insertions(+)
Deleted branch feature/phase1-bootstrap (was df21271).
```

---

## Part C – GitHub OIDC, 3 roles (`terraform/bootstrap/oidc.tf`)

### Step 10 – First design reviewed → redesigned
First plan: `Plan: 4 to add` (1 role + PowerUserAccess, trust on all PRs and `environment:*`).
Review: too broad → redesigned into 3 least-privilege roles:

| Role | Trusted `sub` | Can do |
|---|---|---|
| `mcb-gha-plan` | `:pull_request` | ReadOnly + lock file; Deny secrets, `/mcb/*` SSM, backup reads |
| `mcb-gha-terraform` | `:environment:dev/prod/dr-exception/lab-janitor` (exact) | infra + iam policies with guardrails |
| `mcb-gha-ecr-push` | `:ref:refs/heads/main` | push to `mcb-*` ECR |

Guardrails: region lock · `mcb-*` names · boundary `mcb-workload-boundary` on new roles · Deny editing own roles/boundary/OIDC provider · Deny deleting state/backups · EC2 only t3/t3a medium/large.
```bash
git switch -c feature/phase1-oidc
cd terraform/bootstrap
terraform plan
```
Example output: `Plan: 12 to add, 0 to change, 0 to destroy.`

### Step 11 – Apply → 409 error
```bash
terraform apply
```
Example output:
```
Error: creating IAM OIDC Provider: ... StatusCode: 409 ... EntityAlreadyExists:
Provider with url https://token.actions.githubusercontent.com already exists.
```

### Step 12 – Find who owns the provider
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
aws iam list-roles --query "Roles[?contains(to_string(AssumeRolePolicyDocument), 'token.actions')].RoleName" --output table
```
Example output:
```
"Tags": [ {"Key": "Project", "Value": "devsecops-sre"} ... ]
|  devsecops-sre-dev-github-deploy  |
```
Meaning: my older project (still in progress) owns it → do not take it over.

### Step 13 – Import, then hand back ownership
```bash
terraform import aws_iam_openid_connect_provider.github "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
terraform state rm aws_iam_openid_connect_provider.github
```
Then change `resource "aws_iam_openid_connect_provider" "github"` → `data "aws_iam_openid_connect_provider" "github"` (read-only) and references to `data.aws_iam_openid_connect_provider.github.arn`.
```bash
grep -n "openid_connect_provider" oidc.tf
terraform fmt && terraform validate && terraform plan
```
Example output: `Plan: 9 to add` (12 − 1 provider − 2 already created before the 409).

### Step 14 – Apply and verify roles
```bash
terraform apply
aws iam list-roles --query "Roles[?starts_with(RoleName,'mcb-gha')].RoleName" --output table
aws iam list-attached-role-policies --role-name mcb-gha-terraform --query "AttachedPolicies[].PolicyName"
aws iam get-role --role-name mcb-gha-terraform --query "Role.AssumeRolePolicyDocument.Statement[0].Condition"
```
Example output:
```
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.
|  mcb-gha-ecr-push   |
|  mcb-gha-plan       |
|  mcb-gha-terraform  |
[ "mcb-gha-terraform-iam", "mcb-gha-terraform-infra" ]
"token.actions.githubusercontent.com:sub": [
  "repo:arunkumarm-tech/multi-cloud-banking-devsecops:environment:dev", ... ]
"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
```

### Step 15 – Commit, PR, merge, sync
```bash
git add oidc.tf variables.tf outputs.tf
git commit -m "feat(bootstrap): GitHub OIDC with separate plan, apply and ECR push roles, boundary and guardrails"
git push -u origin feature/phase1-oidc
cd ../.. && git switch main && git pull && git branch -d feature/phase1-oidc
```
Example output: `3 files changed, 456 insertions(+)`

### Step 16 – Create GitHub environments
Navigation: Repo → **Settings** → **Environments** → **New environment**
- `dev`, `lab-janitor`: Deployment branches → **Selected branches and tags** → add `main`
- `prod`, `dr-exception`: same + ✅ **Required reviewers** `arunkumarm-tech` + ❌ untick **Allow administrators to bypass**
- No secrets needed (OIDC).

---

## Part D – VPC + flow logs (`terraform/aws/network/`)

### Step 17 – Branch and write code
```bash
git switch -c feature/phase1-vpc
cd terraform/aws/network
```
Files: `versions.tf`, `backend.tf` (key `aws/network/terraform.tfstate`), `variables.tf`, `main.tf`, `flowlogs.tf`, `outputs.tf`.
What: VPC `mcb-aws-vpc` 10.20.0.0/16 · public 10.20.0.0/24, 10.20.1.0/24 · private 10.20.10.0/24, 10.20.11.0/24 · us-east-1a/1b · IGW · route tables · locked default SG · flow logs ALL → S3 (30 days) · **no NAT** (saves ~USD 32/mo).

### Step 18 – Init and plan
```bash
STATE_BUCKET="mcb-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform fmt && terraform validate && terraform plan
```
Example output:
```
Plan: 21 to add, 0 to change, 0 to destroy.
  + flowlogs_bucket, private_subnet_ids, public_subnet_ids, vpc_id
```
Cost check before apply: VPC, subnets, IGW, route tables, flow logs to S3 = ~USD 0. VPC stays up permanently; only compute gets torn down later.

### Step 19 – Apply and verify
```bash
terraform apply
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query "Subnets[].[Tags[?Key=='Name']|[0].Value,CidrBlock,AvailabilityZone]" --output table
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$(terraform output -raw vpc_id)" \
  --query "FlowLogs[].[FlowLogStatus,LogDestinationType]" --output table
```
Expected output:
```
Apply complete! Resources: 21 added
4 subnets: 10.20.0.0/24, 10.20.1.0/24, 10.20.10.0/24, 10.20.11.0/24 (1a/1b)
ACTIVE | s3
```

### Step 20 – Commit and push
```bash
git add versions.tf backend.tf variables.tf main.tf flowlogs.tf outputs.tf .terraform.lock.hcl
git commit -m "feat(aws): VPC across 2 AZs with locked default SG and S3 flow logs"
git push -u origin feature/phase1-vpc
```

---

## Part E – CI workflow (`.github/workflows/iac-scan.yml`)

### Step 21 – Add repo secret
Navigation: Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
- Name: `AWS_ACCOUNT_ID` · Secret: 12 digits only
Why: hides account ID in public logs (`***`). Not a password; login is OIDC.

### Step 22 – Create workflow and push
Jobs: `checkov` (no AWS access) + `plan` matrix (bootstrap, aws/network): OIDC as `mcb-gha-plan` → `get-caller-identity` → `init -backend-config bucket=mcb-tfstate-${{ secrets.AWS_ACCOUNT_ID }}` → `fmt -check` → `validate` → `plan`. Fork PRs skipped.
```bash
cd ~/Projects/multi-cloud-banking-devsecops
git add .github/workflows/iac-scan.yml
git commit -m "ci: add iac-scan workflow with Checkov and OIDC terraform plan"
git push
```
Open PR #5. Example result: **checkov ✅**, **both plan jobs ❌**.

### Step 23 – Debug: read CloudTrail
Why: CloudTrail shows exactly what GitHub sent.
```bash
aws cloudtrail lookup-events --region us-east-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 6 --query "Events[].CloudTrailEvent" --output json \
| python3 -c 'import sys,json
for e in map(json.loads, json.load(sys.stdin)):
    print(e.get("eventTime"), e.get("errorCode"), (e.get("userIdentity") or {}).get("userName"))'
```
Example output:
```
2026-10-29T00:57:31Z AccessDenied repo:arunkumarm-tech@270752489/multi-cloud-banking-devsecops@1436622021:pull_request
```
Trust expected: `repo:arunkumarm-tech/multi-cloud-banking-devsecops:pull_request` → mismatch.

### Step 24 – Confirm GitHub's subject format
```bash
gh api repos/arunkumarm-tech/multi-cloud-banking-devsecops/actions/oidc/customization/sub
```
Example output:
```json
{ "use_default": true, "use_immutable_subject": true,
  "sub_claim_prefix": "repo:arunkumarm-tech@270752489/multi-cloud-banking-devsecops@1436622021" }
```
Meaning: immutable IDs (owner + repo) → safer; a recreated repo with the same name can't take over the roles.

### Step 25 – Fix trust policies
```bash
cd terraform/bootstrap
cat >> variables.tf <<'TF'

variable "github_oidc_sub_prefix" {
  description = "OIDC sub prefix GitHub sends (immutable owner and repo IDs)"
  type        = string
  default     = "repo:arunkumarm-tech@270752489/multi-cloud-banking-devsecops@1436622021"
}
TF
perl -pi -e 's/^(\s*gh_sub\s*=\s*)"repo:\$\{var\.github_repo\}"/${1}var.github_oidc_sub_prefix/' oidc.tf
grep -n "gh_sub" oidc.tf | head -3
terraform fmt && terraform validate && terraform plan
terraform apply
git add variables.tf oidc.tf
git commit -m "fix(bootstrap): trust GitHub immutable OIDC subject (owner and repo IDs)"
git push
```
Example output: `Plan: 0 to add, 3 to change, 0 to destroy.` → PR checks **green**.
Proof in "Prove identity" step: `arn:aws:sts::***:assumed-role/mcb-gha-plan/iac-scan-pr-5` · plan: **No changes**.

---

## Part F – Checkov triage

### Step 26 – Install and scan locally
```bash
brew install checkov
checkov --version
cd ~/Projects/multi-cloud-banking-devsecops
checkov -d terraform --framework terraform --quiet --compact
```
Example output:
```
3.3.16
Passed checks: 170, Failed checks: 22, Skipped checks: 0
```

### Step 27 – List failures
```bash
checkov -d terraform --framework terraform --quiet -o json | python3 -c 'import sys,json
d=json.load(sys.stdin); d=d if isinstance(d,list) else [d]
for r in d:
    for c in r["results"]["failed_checks"]:
        print(c["check_id"], c["resource"], "-", c["check_name"])' | sort
```
Example output (short):
```
CKV_AWS_109 aws_iam_policy_document.workload_boundary - permissions management without constraints
CKV_AWS_144 aws_s3_bucket.this["state"] - cross-region replication
CKV_AWS_145 aws_s3_bucket.this["state"] - KMS encryption
CKV_AWS_21  aws_s3_bucket.this["state"] - versioning
CKV_AWS_356 aws_iam_policy_document.apply_infra - "*" resource
CKV2_AWS_6  aws_s3_bucket.this["state"] - public access block
...
```

### Step 28 – Decide each finding
| Type | IDs | Action |
|---|---|---|
| 🔴 Real (1) | CKV_AWS_109 | `kms:CreateGrant` only with `kms:GrantIsForAWSResource = true` + region; `iam:CreateServiceLinkedRole` limited to eks, eks-nodegroup, autoscaling, elasticloadbalancing, spot |
| 🟡 False positive (6) | CKV_AWS_21, CKV2_AWS_6, CKV2_AWS_61 | Checkov can't follow `for_each`; proven by `aws s3api` (Step 6) |
| 🟢 Accepted (15) | CKV_AWS_144, 145, 18, CKV2_AWS_62, CKV_AWS_356 | `#checkov:skip=ID:reason` inline (DR is cross-cloud; KMS cost; CloudTrail; no consumer; guardrails + Access Analyzer later) |

### Step 29 – Make Checkov blocking, re-scan, apply
```bash
sed -i '' 's/soft_fail: true/soft_fail: false/' .github/workflows/iac-scan.yml
grep -n "soft_fail" .github/workflows/iac-scan.yml
checkov -d terraform --framework terraform --quiet --compact | head -5
cd terraform/bootstrap
terraform plan | grep -E "Plan:|No changes|will be updated"
terraform apply
```
Example output:
```
Passed checks: 171, Failed checks: 0, Skipped checks: 21
# aws_iam_policy.apply_iam will be updated in-place
# aws_iam_policy.workload_boundary will be updated in-place
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```
```bash
cd ../..
git add terraform/bootstrap/main.tf terraform/bootstrap/oidc.tf terraform/aws/network/flowlogs.tf .github/workflows/iac-scan.yml
git commit -m "sec: fix CKV_AWS_109 in boundary, document accepted Checkov findings, make Checkov blocking"
git push
```
Result: PR #5 green → merged.

---

## Part G – Close Phase 1 (required checks)

### Step 30 – Remove `paths:` filter
Why: required checks must run on **every** PR, or docs-only PRs wait forever.
```bash
git switch main && git pull
git switch -c docs/phase1-close
# python3 script removes the paths: block
grep -n -A2 "pull_request:" .github/workflows/iac-scan.yml
```
Example output:
```
4:  pull_request:
5-    branches: [main]
```
```bash
git add .github/workflows/iac-scan.yml
git commit -m "ci: run iac-scan on every PR (remove paths filter)"
```
Example output: `1 file changed, 3 deletions(-)`

### Step 31 – Day 1 note + PROGRESS.md → PR #6
```bash
git add PROGRESS.md docs/daily-notes/day-01-phase1-aws-foundation.md
git commit -m "docs: Day 1 note and PROGRESS.md - Phase 1 complete"
git push -u origin docs/phase1-close
```
Result: all 3 checks ran on a docs-only PR ✅

### Step 32 – Make checks required
Navigation: Repo → **Settings** → **Rules** → **Rulesets** → `protect-main` → ✅ **Require status checks to pass** → **Add checks**: `checkov`, `plan (terraform/bootstrap)`, `plan (terraform/aws/network)` → **Save changes**
Check: PR → **Conversation** tab → merge box → each check shows **Required** (Checks tab never shows this).

### Step 33 – Merge and sync
```bash
git switch main && git pull && git branch -d docs/phase1-close
```

---

## Failures & fixes
| Problem | Cause | Fix |
|---|---|---|
| Plan 4 → 12 → 9 | Redesign to 3 roles; then provider dropped + 2 resources made before the 409 | Normal; re-plan after each change |
| 409 EntityAlreadyExists | Old `devsecops-sre` project owns GitHub OIDC provider | import → `state rm` → `data` source (Step 13) |
| AssumeRoleWithWebIdentity denied | GitHub sends immutable subject with IDs | CloudTrail + `gh api` → `github_oidc_sub_prefix` (Steps 23–25) |
| Checkov 22 failed | Real + false positives + accepted risk | Fix / prove / skip with reason (Step 28) |
| Secret form: Name empty | Both lines pasted in Secret box | Name = `AWS_ACCOUNT_ID`, Secret = 12 digits |
| Checks didn't run on runbooks PR | Branch made from old main (paths filter) and no PR opened yet | `git rebase main` → `git push --force-with-lease` → open PR |
| 6 warnings on iac-scan | Old Node 20 actions | Follow-up: bump action versions |

## Final verification
```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
aws s3 ls s3://mcb-tfstate-$ACCT/ --recursive
aws iam get-role --role-name mcb-gha-plan --query "Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals"
VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=mcb-aws-vpc --query "Vpcs[0].VpcId" --output text)
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query "Subnets[].[AvailabilityZone,CidrBlock]" --output table
aws ec2 describe-flow-logs --filter Name=resource-id,Values=$VPC --query "FlowLogs[].FlowLogStatus"
```
Expected: `bootstrap/` + `aws/network/` state · `sub` shows immutable prefix · 4 subnets · `ACTIVE`.
GitHub: PR shows 3 green **Required** checks; plan "No changes". Billing → Cost Explorer ≈ USD 0–1.

## Cost
≈ USD 0 – S3 + VPC + IAM only. No NAT, no compute.

## Follow-ups
- Bump Node 20 actions
- `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`
- Delete access key 2 once OIDC covers everything
- Review old `devsecops-sre-dev-github-deploy` trust policy
- Blueprint v1.1: lease files in S3 `leases/` (before Phase 6)
