variable "role_name" {
  description = "IAM role name assumed by GitHub Actions via OIDC"
  type        = string
  default     = "github-actions-deploy"
}

variable "github_repository" {
  description = "GitHub repository in owner/repo format"
  type        = string
}

variable "allowed_environments" {
  description = "GitHub Actions environments allowed to assume the role"
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
  description = "Managed IAM policies attached to the deploy role. Narrower custom policies are preferred long term."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN to reuse. If null, the module creates one."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds for the role"
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Additional tags to apply to OIDC resources"
  type        = map(string)
  default     = {}
}
