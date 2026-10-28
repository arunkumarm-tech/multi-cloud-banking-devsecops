# Day 0 – Phase 0 Setup

**Date:** 2026-10-28
**Phase:** 0 – Repo and account setup

## Goal
Set up the GitHub repo, folder structure and AWS account safety before writing any infrastructure code.

## What I did

1. Created the repo `multi-cloud-banking-devsecops` on GitHub and cloned it.
   ```bash
   git clone https://github.com/arunkumarm-tech/multi-cloud-banking-devsecops.git
   cd multi-cloud-banking-devsecops
   ```

2. Created the folder structure from blueprint v1.0.
   ```bash
   mkdir -p app terraform/{bootstrap,modules,aws,azure,gcp}
   mkdir -p gitops/platform gitops/apps/banking/base
   mkdir -p gitops/apps/banking/overlays/{aws-dev,aws-prod,azure-prod,gcp-prod}
   mkdir -p policies/kyverno monitoring .github/workflows
   mkdir -p docs/{runbooks,daily-notes,incidents}
   ```

3. Added `.gitignore`, `README.md` and `PROGRESS.md`, then pushed.
   ```bash
   git add .
   git commit -m "chore: Phase 0 repo structure"
   git push origin main
   ```

## Verification
- All folders, `.gitignore`, `README.md` and `PROGRESS.md` are visible on GitHub
- All 4 overlays are present: aws-dev, aws-prod, azure-prod, gcp-prod

## Phase 0 checks (pending)
- [ ] `protect-main` ruleset is Active (PR required, no force push, no deletion)
- [ ] MFA is on for the root user and the admin user
- [ ] Budget includes taxes, with alerts at 50% / 80% / 100% forecast

## What I learned
- Freezing the blueprint first keeps the build focused
- Branch protection forces the PR workflow, even when working alone

## Next
Close the Phase 0 checks, then start Phase 1 (Terraform bootstrap, OIDC, VPC).
