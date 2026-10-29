data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  buckets = {
    state  = "mcb-tfstate-${local.account_id}"
    backup = "mcb-backup-${local.account_id}"
  }
}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_144:Lab budget - DR copy is cross-cloud (Azure Blob, GCS) in Phase 9, not S3 CRR
  #checkov:skip=CKV_AWS_145:SSE-S3 AES256 encrypts at rest; customer KMS key cost deferred (USD 20 budget)
  #checkov:skip=CKV_AWS_18:Bucket config changes covered by CloudTrail; access-log bucket deferred
  #checkov:skip=CKV2_AWS_62:No consumer for S3 event notifications
  #checkov:skip=CKV_AWS_21:False positive - versioning set via for_each resource, verified with s3api
  #checkov:skip=CKV2_AWS_6:False positive - public access block set via for_each resource, verified with s3api
  #checkov:skip=CKV2_AWS_61:False positive - lifecycle set via for_each resource
  for_each = local.buckets
  bucket   = each.value

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "tls_only" {
  for_each = aws_s3_bucket.this

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  policy   = data.aws_iam_policy_document.tls_only[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
