locals {
  environment_subjects = [
    for environment in var.allowed_environments :
    "repo:${var.github_repository}:environment:${environment}"
  ]

  branch_subjects = [
    for branch in var.allowed_branches :
    "repo:${var.github_repository}:ref:${branch}"
  ]

  allowed_subjects = concat(
    local.environment_subjects,
    local.branch_subjects,
    var.additional_subjects,
  )

  oidc_provider_arn = coalesce(
    var.existing_oidc_provider_arn,
    try(aws_iam_openid_connect_provider.github[0].arn, null),
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_oidc_provider_arn == null ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  tags = merge(var.tags, {
    Name      = "github-actions-oidc"
    ManagedBy = "terraform"
  })
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  description          = "Deploy role for GitHub Actions via OIDC"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = var.max_session_duration

  tags = merge(var.tags, {
    Name      = var.role_name
    ManagedBy = "terraform"
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}
