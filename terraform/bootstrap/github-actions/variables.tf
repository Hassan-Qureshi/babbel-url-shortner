variable "aws_region" {
  description = "AWS region for the bootstrap stack"
  type        = string
  default     = "eu-central-1"
}

variable "github_repository" {
  description = "GitHub repository in owner/repo format"
  type        = string
}

variable "role_name" {
  description = "IAM role name assumed by GitHub Actions"
  type        = string
  default     = "github-actions-deploy"
}

variable "allowed_environments" {
  description = "GitHub Actions environments allowed to assume the deploy role"
  type        = list(string)
  default     = ["dev", "staging", "production"]
}

variable "allowed_branches" {
  description = "Git refs allowed to assume the role, e.g. refs/heads/main"
  type        = list(string)
  default     = []
}

variable "additional_subjects" {
  description = "Additional GitHub OIDC subject patterns allowed to assume the role"
  type        = list(string)
  default     = []
}

variable "managed_policy_arns" {
  description = "Managed IAM policies attached to the deploy role"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN to reuse. If null, a provider is created."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to bootstrap resources"
  type        = map(string)
  default     = {}
}
