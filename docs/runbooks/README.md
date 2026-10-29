# Runbooks – Multi-Cloud Banking DevSecOps

Replay guide for every phase. Each runbook: Goal → Prerequisites → Steps → Failures & fixes → Verification → Cost.

| Phase | Runbook | Status |
|---|---|---|
| 0 | [Setup](phase-00-setup.md) | ✅ |
| 1 | [AWS foundation](phase-01-aws-foundation.md) | ✅ |
| 2 | App + secure CI | ⏳ |
| 3 | Kubernetes + GitOps | ⏳ |
| 4 | Kafka events | ⏳ |
| 5 | Observability / SRE | ⏳ |
| 6 | V1→V2 on EKS (manager demo) | ⏳ |
| 7 | Azure warm standby | ⏳ |
| 8 | GCP cold standby | ⏳ |
| 9 | DR drill | ⏳ |
| 10 | Hardening + interview pack | ⏳ |

Rules: never commit account IDs, keys or passwords. Use `$ACCT` in commands.
