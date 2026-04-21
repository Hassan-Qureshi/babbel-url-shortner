output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = local.oidc_provider_arn
}

output "role_arn" {
  description = "ARN of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions.name
}

output "allowed_subjects" {
  description = "GitHub OIDC subjects allowed to assume the role"
  value       = local.allowed_subjects
}
