output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions deploy role"
  value       = module.github_actions_oidc.role_arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions deploy role"
  value       = module.github_actions_oidc.role_name
}

output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = module.github_actions_oidc.oidc_provider_arn
}

output "allowed_subjects" {
  description = "GitHub OIDC subjects allowed to assume the deploy role"
  value       = module.github_actions_oidc.allowed_subjects
}
