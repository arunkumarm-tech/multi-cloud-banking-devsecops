locals {
  account_id    = data.aws_caller_identity.current.account_id
  flowlogs_name = "mcb-flowlogs-${local.account_id}"
}

resource "aws_s3_bucket" "flowlogs" {
  bucket = local.flowlogs_name
}

resource "aws_s3_bucket_versioning" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.flowlogs]
}

data "aws_iam_policy_document" "flowlogs" {
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flowlogs.arn}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${var.region}:${local.account_id}:*"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.flowlogs.arn]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.flowlogs.arn, "${aws_s3_bucket.flowlogs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id
  policy = data.aws_iam_policy_document.flowlogs.json

  depends_on = [aws_s3_bucket_public_access_block.flowlogs]
}

resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.flowlogs.arn
  max_aggregation_interval = 600

  tags = { Name = "mcb-vpc-flow-log" }

  depends_on = [aws_s3_bucket_policy.flowlogs]
}
