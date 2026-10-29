## Last session: 2026-10-28
Phase: 1 AWS foundation ✅ Complete | Day: 1
Done: state + backup S3 buckets (versioning, SSE, public block, TLS-only); state moved to S3 with lockfile; GitHub OIDC with 3 least-privilege roles (plan, terraform, ecr-push); VPC 10.20.0.0/16 with 2 public + 2 private subnets, no NAT; VPC flow logs to S3; iac-scan CI (Checkov blocking + Terraform plan via OIDC); 4 GitHub environments
In progress: add 3 required status checks to protect-main
Blocked: none
Next step: start Phase 2 (4 FastAPI services, ECR, ci-app.yml)
Resources left running: VPC + subnets, S3 buckets (state, backup, flowlogs), IAM roles (near USD 0)
Hours used this month: Dev 0 h, EKS 0 h
