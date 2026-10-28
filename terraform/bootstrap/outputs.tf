output "state_bucket" {
  value = aws_s3_bucket.this["state"].id
}

output "backup_bucket" {
  value = aws_s3_bucket.this["backup"].id
}

output "gha_terraform_role_arn" {
  value = aws_iam_role.gha_terraform.arn
}

output "gha_plan_role_arn" {
  value = aws_iam_role.gha_plan.arn
}

output "gha_ecr_push_role_arn" {
  value = aws_iam_role.gha_ecr_push.arn
}
