# Day 1 – Phase 1 AWS Foundation (2026-10-28)

## What I did
- Built Terraform bootstrap: 2 S3 buckets (state, backup) with versioning, encryption, public block, TLS-only policy
- Moved Terraform state from laptop to S3 (use_lockfile, no DynamoDB)
- Created GitHub OIDC trust + 3 roles: mcb-gha-plan (PR, read-only), mcb-gha-terraform (environments), mcb-gha-ecr-push (main)
- Built VPC mcb-aws-vpc: 2 public + 2 private subnets in 2 AZs, IGW, no NAT (saves about USD 32/month)
- Enabled VPC flow logs to S3, 30-day retention
- Created iac-scan workflow: Checkov + terraform fmt/validate/plan using OIDC
- Created GitHub environments: dev, lab-janitor, prod, dr-exception

## Problems and fixes
- OIDC provider already existed (409) from my old project -> used it as a data source instead of creating it
- GitHub could not assume role (AssumeRoleWithWebIdentity denied) -> CloudTrail showed GitHub sends the immutable subject format -> updated trust policy sub
- Checkov: 22 failures -> fixed 1 real issue (KMS CreateGrant), 6 false positives, 15 accepted with skip reasons -> 0 failed

## What I learned
- OIDC = no long-lived AWS keys in GitHub
- Always check CloudTrail to see the real error details
- Checkov cannot follow for_each, so verify with AWS CLI

## Cost today
About USD 0 (S3 + VPC only, no compute)
