output "state_bucket" {
  value = aws_s3_bucket.this["state"].id
}

output "backup_bucket" {
  value = aws_s3_bucket.this["backup"].id
}
