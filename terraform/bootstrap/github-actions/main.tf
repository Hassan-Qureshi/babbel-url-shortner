provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project   = "url-shortener"
      ManagedBy = "terraform"
      Stack     = "github-actions-bootstrap"
    })
  }
}

module "github_actions_oidc" {
  source = "../../modules/github-actions-oidc"

  role_name                  = var.role_name
  github_repository          = var.github_repository
  allowed_environments       = var.allowed_environments
  allowed_branches           = var.allowed_branches
  additional_subjects        = var.additional_subjects
  managed_policy_arns        = var.managed_policy_arns
  existing_oidc_provider_arn = var.existing_oidc_provider_arn

  tags = var.tags
}
