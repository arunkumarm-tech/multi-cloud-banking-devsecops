locals {
  gh_sub     = var.github_oidc_sub_prefix
  iam_prefix = "arn:aws:iam::${local.account_id}"
  state_arn  = aws_s3_bucket.this["state"].arn
  backup_arn = aws_s3_bucket.this["backup"].arn
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------- Trust policies ----------

data "aws_iam_policy_document" "trust_plan" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.gh_sub}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for env in var.deploy_environments : "${local.gh_sub}:environment:${env}"]
    }
  }
}

data "aws_iam_policy_document" "trust_ecr_push" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.gh_sub}:ref:refs/heads/main"]
    }
  }
}

# ---------- Permissions boundary for every mcb-* workload role ----------

data "aws_iam_policy_document" "workload_boundary" {
  #checkov:skip=CKV_AWS_356:Region-locked, Deny guardrails and boundary; tighten with Access Analyzer after Phase 6
  statement {
    sid    = "WorkloadServicesInRegion"
    effect = "Allow"
    actions = [
      "ec2:*", "elasticloadbalancing:*", "autoscaling:*", "eks:*",
      "logs:*", "cloudwatch:*", "ssm:*", "ssmmessages:*", "ec2messages:*",
      "ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability", "ecr:DescribeImages", "ecr:DescribeRepositories",
      "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "ReadMcbSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:mcb/*"]
  }

  statement {
    sid       = "BackupBucketOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.backup_arn, "${local.backup_arn}/*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "autoscaling.amazonaws.com",
        "elasticloadbalancing.amazonaws.com", "spot.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "KmsGrantsForAwsServicesOnly"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name   = "mcb-workload-boundary"
  policy = data.aws_iam_policy_document.workload_boundary.json
}

# ---------- Role 1: mcb-gha-plan (PR validation, read-only) ----------

data "aws_iam_policy_document" "plan_guardrails" {
  statement {
    sid       = "StateLockfileOnly"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/*.tflock"]
  }

  statement {
    sid       = "NoSecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  statement {
    sid       = "NoMcbParameters"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:*:${local.account_id}:parameter/mcb/*"]
  }

  statement {
    sid       = "NoBackupReads"
    effect    = "Deny"
    actions   = ["s3:GetObject"]
    resources = ["${local.backup_arn}/*"]
  }
}

resource "aws_iam_role" "gha_plan" {
  name                 = "mcb-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "gha_plan_guardrails" {
  name   = "mcb-gha-plan-guardrails"
  role   = aws_iam_role.gha_plan.id
  policy = data.aws_iam_policy_document.plan_guardrails.json
}

# ---------- Role 2: mcb-gha-terraform (apply, protected environments only) ----------

data "aws_iam_policy_document" "apply_infra" {
  #checkov:skip=CKV_AWS_356:Region-locked, Deny guardrails and boundary; tighten with Access Analyzer after Phase 6
  statement {
    sid    = "RegionalInfra"
    effect = "Allow"
    actions = [
      "ec2:*", "elasticloadbalancing:*", "autoscaling:*", "eks:*",
      "logs:*", "cloudwatch:*",
      "ssm:GetParameter", "ssm:GetParameters", "ssm:DescribeParameters",
      "ecr:GetAuthorizationToken", "ecr:DescribeRepositories",
      "secretsmanager:ListSecrets", "secretsmanager:GetRandomPassword",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "McbEcrRepos"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/mcb-*"]
  }

  statement {
    sid       = "McbSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:mcb/*"]
  }

  statement {
    sid       = "S3Discovery"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
    resources = ["*"]
  }

  statement {
    sid       = "McbBuckets"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::mcb-*", "arn:aws:s3:::mcb-*/*"]
  }

  statement {
    sid    = "ProtectStateAndBackupBucketConfig"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration",
      "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration",
      "s3:PutBucketOwnershipControls", "s3:PutBucketAcl",
    ]
    resources = [local.state_arn, local.backup_arn]
  }

  statement {
    sid       = "ProtectStateHistory"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${local.state_arn}/*", "${local.backup_arn}/*"]
  }

  statement {
    sid       = "ProtectBackups"
    effect    = "Deny"
    actions   = ["s3:DeleteObject"]
    resources = ["${local.backup_arn}/*"]
  }

  statement {
    sid       = "CostGuardInstanceTypes"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "StringNotEquals"
      variable = "ec2:InstanceType"
      values   = var.allowed_instance_types
    }
  }
}

data "aws_iam_policy_document" "apply_iam" {
  #checkov:skip=CKV_AWS_356:Region-locked, Deny guardrails and boundary; tighten with Access Analyzer after Phase 6
  statement {
    sid       = "IamRead"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid    = "RolesOnlyWithBoundary"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:PutRolePermissionsBoundary",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
    ]
    resources = ["${local.iam_prefix}:role/mcb-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid    = "ManageMcbRoles"
    effect = "Allow"
    actions = [
      "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
      "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy", "iam:PassRole",
    ]
    resources = ["${local.iam_prefix}:role/mcb-*"]
  }

  statement {
    sid    = "ManageMcbPolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = ["${local.iam_prefix}:policy/mcb-*"]
  }

  statement {
    sid    = "ManageMcbInstanceProfiles"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
    ]
    resources = ["${local.iam_prefix}:instance-profile/mcb-*"]
  }

  statement {
    sid    = "EksIrsaProviders"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider",
    ]
    resources = ["${local.iam_prefix}:oidc-provider/oidc.eks.${var.region}.amazonaws.com/*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "autoscaling.amazonaws.com",
        "elasticloadbalancing.amazonaws.com", "spot.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "ProtectPipelineIdentity"
    effect = "Deny"
    actions = [
      "iam:Create*", "iam:Delete*", "iam:Update*", "iam:Put*", "iam:Attach*",
      "iam:Detach*", "iam:Tag*", "iam:Untag*", "iam:Set*", "iam:Add*",
      "iam:Remove*", "iam:PassRole",
    ]
    resources = [
      "${local.iam_prefix}:role/mcb-gha-*",
      "${local.iam_prefix}:policy/mcb-gha-*",
      aws_iam_policy.workload_boundary.arn,
      data.aws_iam_openid_connect_provider.github.arn,
    ]
  }

  statement {
    sid       = "NoBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "gha_terraform" {
  name                 = "mcb-gha-terraform"
  assume_role_policy   = data.aws_iam_policy_document.trust_apply.json
  max_session_duration = 3600
}

resource "aws_iam_policy" "apply_infra" {
  name   = "mcb-gha-terraform-infra"
  policy = data.aws_iam_policy_document.apply_infra.json
}

resource "aws_iam_policy" "apply_iam" {
  name   = "mcb-gha-terraform-iam"
  policy = data.aws_iam_policy_document.apply_iam.json
}

resource "aws_iam_role_policy_attachment" "gha_terraform_infra" {
  role       = aws_iam_role.gha_terraform.name
  policy_arn = aws_iam_policy.apply_infra.arn
}

resource "aws_iam_role_policy_attachment" "gha_terraform_iam" {
  role       = aws_iam_role.gha_terraform.name
  policy_arn = aws_iam_policy.apply_iam.arn
}

# ---------- Role 3: mcb-gha-ecr-push (CI image push from main) ----------

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushMcbRepos"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
      "ecr:DescribeImages", "ecr:DescribeRepositories",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/mcb-*"]
  }
}

resource "aws_iam_role" "gha_ecr_push" {
  name                 = "mcb-gha-ecr-push"
  assume_role_policy   = data.aws_iam_policy_document.trust_ecr_push.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "gha_ecr_push" {
  name   = "mcb-gha-ecr-push"
  role   = aws_iam_role.gha_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
