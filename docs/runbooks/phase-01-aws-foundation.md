# Phase 1 – AWS Foundation

**Goal:** remote Terraform state, keyless GitHub→AWS login (OIDC), VPC, security scan + plan on every PR.
**Prerequisites:** Phase 0 done, Terraform installed, AWS CLI logged in as `arun-devops`.

```bash
export ACCT=$(aws sts get-caller-identity --query Account --output text)
export STATE_BUCKET=mcb-tfstate-$ACCT
```

## A. Bootstrap – state and backup buckets (`terraform/bootstrap/`)

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 1 | `git switch -c feature/phase1-bootstrap` | Work on a branch | New branch |
| 2 | Write `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf` | 2 buckets via `for_each`: tfstate + backup | Code ready |
| 3 | Each bucket: versioning, AES256, public block, BucketOwnerEnforced, 90-day noncurrent expiry, TLS-only policy, `prevent_destroy` | Bank-grade bucket hardening | 7 controls per bucket |
| 4 | `cd terraform/bootstrap && terraform init` | Download AWS provider | Initialized |
| 5 | `terraform fmt && terraform validate` | Format + syntax check | Valid |
| 6 | `terraform plan` | Preview changes | 14 to add |
| 7 | `terraform apply` | Create buckets | 14 added |
| 8 | `aws s3api get-bucket-versioning --bucket $STATE_BUCKET` | Prove versioning | `Enabled` |
| 9 | `aws s3api get-public-access-block --bucket $STATE_BUCKET` | Prove public block | All 4 `true` |
| 10 | Add `backend.tf` (S3, key `bootstrap/terraform.tfstate`, `use_lockfile = true`, no bucket name) | Move state to S3, keep account ID out of repo | Backend defined |
| 11 | `terraform init -migrate-state -backend-config="bucket=$STATE_BUCKET"` | Copy local state to S3 | State in S3 |
| 12 | `mv terraform.tfstate* ~/mcb-state-backup/` | Remove local copies safely | Local clean |

## B. GitHub OIDC – 3 least-privilege roles (`oidc.tf`)

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 13 | Role `mcb-gha-plan`, trust `:pull_request`, ReadOnly + lock write, Deny secrets/SSM/backup reads | PRs can only read + plan | Plan role |
| 14 | Role `mcb-gha-terraform`, trust exact environments dev/prod/dr-exception/lab-janitor | Only approved environments can apply | Apply role |
| 15 | Role `mcb-gha-ecr-push`, trust `:ref:refs/heads/main` | Only main pushes images | ECR role |
| 16 | Apply-role guardrails: region lock, `mcb-*` names, permissions boundary `mcb-workload-boundary`, Deny touching own roles/state/backups, EC2 type limit | Limit blast radius | Guardrails in place |
| 17 | `terraform plan && terraform apply` | Create roles | ❌ 409 EntityAlreadyExists (see fixes) |
| 18 | `aws iam list-roles --query "Roles[?starts_with(RoleName,'mcb-gha')].RoleName"` | Prove 3 roles exist | 3 names |
| 19 | `aws iam get-role --role-name mcb-gha-plan --query "Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals"` | Check trust condition | aud + sub shown |
| 20 | PR → merge → sync | Save work | Merged |

## C. VPC + flow logs (`terraform/aws/network/`)

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 21 | `git switch -c feature/phase1-vpc` | New branch | Branch |
| 22 | Write `versions.tf`, `backend.tf` (key `aws/network/terraform.tfstate`), `variables.tf`, `main.tf`, `outputs.tf` | Network stack, own state file | Code ready |
| 23 | VPC `mcb-aws-vpc` 10.20.0.0/16; public 10.20.0.0/24 + 10.20.1.0/24; private 10.20.10.0/24 + 10.20.11.0/24; us-east-1a/1b | 2 AZs for HA | Subnets planned |
| 24 | IGW, public + private route tables, locked default SG, **no NAT** | Internet for public only; save ~USD 32/mo | Routing ready |
| 25 | `flowlogs.tf`: bucket `mcb-flowlogs-<acct>`, flow log ALL traffic, 30-day retention | Network audit trail | Logging ready |
| 26 | `terraform init -backend-config="bucket=$STATE_BUCKET"` | Connect to S3 state | Initialized |
| 27 | `terraform plan && terraform apply` | Create network | 21 added |
| 28 | `aws ec2 describe-subnets --filters Name=vpc-id,Values=<vpc-id> --query "Subnets[].CidrBlock"` | Prove 4 subnets | 4 CIDRs |
| 29 | `aws ec2 describe-flow-logs --query "FlowLogs[].FlowLogStatus"` | Prove flow log | `ACTIVE` |
| 30 | `aws s3 ls s3://$STATE_BUCKET/ --recursive` | Both states in S3 | bootstrap/ + aws/network/ |

## D. CI – iac-scan workflow (`.github/workflows/iac-scan.yml`)

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 31 | Repo → Settings → Secrets and variables → Actions → New secret `AWS_ACCOUNT_ID` | Account ID hidden in public repo | Secret saved |
| 32 | Job `checkov` (no AWS access) | Security scan of Terraform | Scan job |
| 33 | Job `plan` matrix (bootstrap, aws/network): OIDC as `mcb-gha-plan` → `get-caller-identity` → init → fmt -check → validate → plan | Prove code matches AWS on every PR | Plan jobs |
| 34 | Skip fork PRs | Forks must never get AWS access | Safe |
| 35 | Push → open PR → watch Checks tab | First run | ❌ AssumeRoleWithWebIdentity denied (see fixes) |
| 36 | After fix: "Prove identity" step shows `assumed-role/mcb-gha-plan/...` | Proof OIDC works | ✅ |
| 37 | Plan output | Code = AWS | "No changes" |

## E. Checkov triage

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 38 | `checkov -d terraform` | Local scan | 170 passed / 22 failed |
| 39 | Fix `CKV_AWS_109`: KMS `CreateGrant` only with `kms:GrantIsForAWSResource` + region; limit `CreateServiceLinkedRole` to eks/autoscaling/elb/spot | Real risk | Fixed |
| 40 | `CKV_AWS_21`, `CKV2_AWS_6`, `CKV2_AWS_61` → verify with `aws s3api` | Checkov cannot follow `for_each` | 6 false positives |
| 41 | Add `#checkov:skip=ID:reason` for CKV_AWS_144/145/18, CKV2_AWS_62, CKV_AWS_356 | Accepted risk, documented | 15 skipped |
| 42 | Re-run `checkov -d terraform` | Confirm | 171 passed / 0 failed / 21 skipped |
| 43 | Set `soft_fail: false` in workflow | New issues now block PRs | Blocking |

## F. Environments and required checks

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 44 | Settings → Environments → `dev`, `lab-janitor`: deployment branch `main` only | Apply only from main | 1 rule each |
| 45 | `prod`, `dr-exception`: branch `main` + required reviewer `arunkumarm-tech`, admin bypass off | Human approval for risky envs | 2 rules each |
| 46 | Remove `paths:` filter from `iac-scan.yml` (branch `docs/phase1-close`) | Required checks must run on every PR, even docs | Runs always |
| 47 | Add Day 1 note + update PROGRESS.md → push → PR #6 | Close Phase 1 | All 3 checks green on docs-only PR |
| 48 | Settings → Rules → Rulesets → `protect-main` → Require status checks → add `checkov`, `plan (terraform/bootstrap)`, `plan (terraform/aws/network)` → Save | Nothing merges without scan + plans | Checks show **Required** |
| 49 | Merge PR #6 → `git switch main && git pull && git branch -d docs/phase1-close` | Sync | Phase 1 ✅ |

## Failures & fixes

| Problem | Cause | Fix |
|---|---|---|
| `CreateOpenIDConnectProvider` 409 EntityAlreadyExists | Old `devsecops-sre` project already owns the GitHub OIDC provider | `terraform import`, then `terraform state rm`, then use `data "aws_iam_openid_connect_provider"` (read-only) |
| Plan count changed 4 → 12 → 9 | Redesign to 3 roles, then 2 resources created before the 409, then provider became data source | Normal; re-plan after each change |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | GitHub sends the **immutable** subject (`repo:owner@id/repo@id:...`) | Found with `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity`; confirmed with `gh api repos/arunkumarm-tech/multi-cloud-banking-devsecops/actions/oidc/customization/sub`; added variable `github_oidc_sub_prefix` |
| Checkov 22 failures | Mix of real, false positive, accepted | Fix / verify / skip with reason |
| Required checks would hang on docs PRs | `paths:` filter skipped the workflow | Removed filter |

## Verification
- `aws s3 ls s3://$STATE_BUCKET/ --recursive` → bootstrap/ and aws/network/ state
- 3 `mcb-gha-*` roles exist; trust shows exact `sub`
- 4 subnets; flow log `ACTIVE`
- PR shows 3 green **Required** checks; plan "No changes"
- Billing → Cost Explorer ≈ USD 0–1

## Cost
≈ USD 0 – S3 + VPC + IAM only. No NAT, no compute. VPC stays up permanently.

## Follow-ups
- Bump Node 20 actions (6 warnings)
- `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`
- Delete access key 2 once OIDC covers everything
- Review old `devsecops-sre-dev-github-deploy` trust policy
- Blueprint v1.1: lease files in S3 `leases/` prefix (before Phase 6)
