# Phase 0 – Setup

**Goal:** safe repo, protected main branch, secure AWS login, cost alarm.
**Prerequisites:** GitHub account, AWS account, Git + AWS CLI on laptop, authenticator app.

## Steps

| # | Command / Navigation | Why | Result |
|---|---|---|---|
| 1 | GitHub → New repository → `multi-cloud-banking-devsecops` (Public) | One home for all code and docs | Repo created |
| 2 | `git clone <repo-url> && cd multi-cloud-banking-devsecops` | Work locally | Local copy |
| 3 | `mkdir -p terraform docs/daily-notes .github/workflows` | Standard folder layout | Folders ready |
| 4 | Create `.gitignore` (`.terraform/`, `*.tfstate*`, `*.tfvars`) | Never push state or secrets | State stays local |
| 5 | Create `README.md` and `PROGRESS.md` | Show project + track status | Files added |
| 6 | `git add . && git commit -m "init" && git push` | Save to GitHub | Pushed to main |
| 7 | Repo → Settings → Rules → Rulesets → New branch ruleset | Protect main | Form opens |
| 8 | Name `protect-main`, Enforcement **Active**, Target **default branch**, bypass empty | Rules apply to everyone, even me | Ruleset set |
| 9 | Tick Restrict deletions, Require PR before merging, Block force pushes → Save | No direct/force push to main | Ruleset active |
| 10 | AWS (root) → account menu → Security credentials → Assign MFA → Authenticator app | Protect root account | Root MFA on |
| 11 | IAM → Users → `arun-devops` → Security credentials → Enable console access (custom password) | Stop using root daily | Console login works |
| 12 | Same page → Assign MFA → `arun-devops-mfa` | Protect admin user | MFA on |
| 13 | IAM → Users → `arun-devops` → Groups → `DevOps-Administrators` | Admin rights via group, not user | AdministratorAccess |
| 14 | Security credentials → Access key 1 (unused) → Deactivate | Remove unused secrets | Key 1 inactive |
| 15 | Login in incognito as `arun-devops` + MFA | Prove new login works | Login OK |
| 16 | Billing → Budgets → Create budget → Cost budget, Monthly, USD 20 | Cost guard | Budget created |
| 17 | Budget options: include tax, exclude only Credit/Refund | Real total incl. 16% IVA | Correct amount |
| 18 | Alerts: Actual 85%, Actual 100%, Forecasted 100% → email | Early warning | 3 alerts |
| 19 | Confirm alert email | Alerts actually arrive | Email verified |
| 20 | `git switch -c docs/day-00` → add `docs/daily-notes/day-00-phase0-setup.md` → push → PR → merge | Practise PR flow (main is protected) | PR #2 merged |
| 21 | `git switch main && git pull && git branch -d docs/day-00` | Sync laptop | Clean main |

## Git cycle (used every time)
branch → edit → `git add` → `git commit` → `git push` → PR → merge → `git switch main && git pull && git branch -d <branch>`

## Failures & fixes
| Problem | Fix |
|---|---|
| Cannot push to main directly | Expected – ruleset works; always use a branch + PR |
| Required status checks not possible yet | No CI existed → moved to Phase 1 |

## Verification
- PR to main is required (direct push rejected)
- Root and `arun-devops` ask for MFA
- Budget shows USD 20 with 3 alerts, email verified

## Cost
USD 0
