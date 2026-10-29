# Phase 0 – Setup (detailed runbook)

**Goal:** repo with folder layout, protected `main`, secure AWS login with MFA, cost budget with alerts.
**Prerequisites:** GitHub account, AWS account, Git + AWS CLI on Mac, Google Authenticator.
**Account ID:** always masked as `XXXXXXXXXXXX` (public repo).

---

## Part A – Repo and folders

### Step 1 – Clone the repo
Why: work locally, push through PRs.
```bash
git clone https://github.com/arunkumarm-tech/multi-cloud-banking-devsecops.git
cd multi-cloud-banking-devsecops
```

### Step 2 – Create the folder layout (blueprint v1.0)
Why: one place for app, infra, GitOps, policies, monitoring, docs.
```bash
mkdir -p app terraform/{bootstrap,modules,aws,azure,gcp}
mkdir -p gitops/platform gitops/apps/banking/base
mkdir -p gitops/apps/banking/overlays/{aws-dev,aws-prod,azure-prod,gcp-prod}
mkdir -p policies/kyverno monitoring .github/workflows
mkdir -p docs/{runbooks,daily-notes,incidents}
```

### Step 3 – Add .gitignore, README.md, PROGRESS.md and push
Why: never push state/secrets; track progress.
```bash
grep -E "tfstate|\.terraform" .gitignore
```
Example output:
```
.terraform/
*.tfstate
*.tfstate.*
```
```bash
git add .
git commit -m "chore: Phase 0 repo structure"
git push origin main
```
Result: all folders + 4 overlays visible on GitHub.

---

## Part B – Protect main (GitHub ruleset)

### Step 4 – Create ruleset `protect-main`
Why: nobody (not even me) can push, force-push or delete `main` directly.
Navigation: Repo → **Settings** → **Rules** → **Rulesets** → **New ruleset** → **New branch ruleset**
- Ruleset name: `protect-main`
- Enforcement status: **Active**
- Target branches: **Add target** → **Include default branch** (shows `main`)
- Bypass list: **empty**
- Rules ticked: ✅ Restrict deletions · ✅ Require a pull request before merging (0 approvals) · ✅ Block force pushes
- Click **Create**

Example result: Rulesets page shows `protect-main` → **Active**.

---

## Part C – AWS login security

### Step 5 – Check root MFA
Why: root is the most powerful login.
Navigation: sign in as root → account name (top right) → **Security credentials** → **Multi-factor authentication (MFA)**
Example result:
```
Virtual  arn:aws:iam::XXXXXXXXXXXX:mfa/arunmxbox  Sun Apr 12 2026
```

### Step 6 – Inspect existing user `arun-devops`
Why: reuse an existing user instead of creating a new admin.
Navigation: **IAM** → **Users** → `arun-devops` → **Security credentials**
Example finding:
```
Console access: Disabled | MFA: 0 | Access key 1: last used 68 days | Access key 2: last used 26 days
```

### Step 7 – Enable console access
Navigation: Security credentials → **Enable console access** → **Custom password** → **Apply**
Why: daily login without root.
Tip: save password + sign-in URL in Chrome → ⋮ → **Passwords and autofill** → **Google Password Manager** → **Add**. CSV download not needed.

### Step 8 – Assign MFA to `arun-devops`
Navigation: Security credentials → **Assign MFA device** → name `arun-devops-mfa` → **Authenticator app** → scan QR → enter 2 codes → **Add MFA**
Example result: `MFA (1)`

### Step 9 – Deactivate unused access key 1
Why: unused keys are risk; blueprint = OIDC, no static keys.
Navigation: Access keys → key used 68 days ago → **Actions** → **Deactivate**
Example result: key 1 **Inactive**, key 2 **Active** (kept for local Terraform until OIDC covers everything).

### Step 10 – Confirm admin rights
Navigation: `arun-devops` → **Groups** tab
Example result: group `DevOps-Administrators` → **AdministratorAccess**

### Step 11 – Test login in incognito
Why: prove the new login works before leaving root.
Navigation: incognito → sign-in URL → `arun-devops` + password + MFA
Result: login OK. From now on use `arun-devops`, sign out of root.

### Step 12 – Confirm CLI identity
```bash
aws sts get-caller-identity
```
Example output:
```json
{
  "UserId": "AIDA...",
  "Account": "XXXXXXXXXXXX",
  "Arn": "arn:aws:iam::XXXXXXXXXXXX:user/arun-devops"
}
```

---

## Part D – Budget

### Step 13 – Check budget amount and alerts
Navigation: search **Budgets** → **Billing and Cost Management** → **Budgets** → `AWS devops monthly buget`
Example result:
```
Amount: $20.00 monthly | Spent: $0.24 | Forecast: $0.32
Alerts: Actual 85% | Actual 100% | Forecasted 100%
```

### Step 14 – Verify alert email
Why: without verification, alerts never arrive.
Navigation: same page → **Email verification** → select email → **Send verifications** → click link in inbox (check spam)
Example result: `runmxbox@gmail.com  Verified`

### Step 15 – Check tax is included
Navigation: same page → **▶ Additional budget parameters**
Example output:
```
Included filters: None
Excluded filters: Charge type: Credit, Refund
```
Meaning: tax counted (16% IVA); credits don't hide real cost.

---

## Part E – Day 0 note through a PR

### Step 16 – Branch, add note, push
```bash
git switch main && git pull
git switch -c feature/day-00-notes
git add docs/daily-notes/day-00-phase0-setup.md
git commit -m "docs: add Day 0 Phase 0 setup note"
git push -u origin feature/day-00-notes
```
Example output:
```
[feature/day-00-notes 633abb7] docs: add Day 0 Phase 0 setup note
 1 file changed, 47 insertions(+)
```

### Step 17 – PR → merge → sync
Navigation: GitHub → **Compare & pull request** → **Create pull request** → **Merge pull request** → **Confirm merge** → **Delete branch**
```bash
git switch main
git pull
git branch -d feature/day-00-notes
```

### Step 18 – Close Phase 0 checks (PR #2)
```bash
git switch -c docs/day-00-close
# edit note + PROGRESS.md (open -e PROGRESS.md)
git add docs/daily-notes/day-00-phase0-setup.md PROGRESS.md
git commit -m "docs: close Phase 0 checks"
git push -u origin docs/day-00-close
```
Example output after merge:
```
3292c0f (HEAD -> main, origin/main) Merge pull request #2 from arunkumarm-tech/docs/day-00-close
```

---

## Git cycle (every change)
branch → edit → `git add` → `git commit` → `git push` → PR → merge → `git switch main && git pull && git branch -d <branch>`

## Failures & fixes
| Problem | Cause | Fix |
|---|---|---|
| Rulesets page empty | Ruleset never created | Created `protect-main` (Step 4) |
| `fatal: a branch named 'feature/day-00-notes' already exists` | Branch created earlier | `git switch feature/day-00-notes` instead of `-c` |
| `zsh: command not found: #` | Pasted a comment line | Harmless; skip `#` lines |
| `pathspec 'docs/daily-notes/...' did not match any files` | Ran git inside `docs/daily-notes/` | `cd ../..` to repo root, or use plain file name |
| `cd: no such file or directory: ~/multi-cloud-banking-devsecops` | Repo is under `~/Projects/` | `cd ~/Projects/multi-cloud-banking-devsecops` |
| Incognito login asked password reset | "Must create new password" stayed ticked | Reset once, update Password Manager |
| Budget email 0/1 | Not verified | Send verifications (Step 14) |
| Required status checks | No CI yet | Moved to Phase 1 |

## Final verification
- `protect-main` Active, 3 rules, bypass empty
- Root + `arun-devops` MFA; key 1 Inactive
- Budget USD 20, tax included, 3 alerts, email verified
- Day 0 note on `main` (PR #2)

## Cost
USD 0
