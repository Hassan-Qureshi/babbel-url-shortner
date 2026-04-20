output "function_arns" {
  description = "Map of function name to Lambda function ARN"
  value       = { for k, v in aws_lambda_function.this : k => v.arn }
}

output "function_invoke_arns" {
  description = "Map of function name to Lambda invoke ARN"
  value       = { for k, v in aws_lambda_function.this : k => v.invoke_arn }
}

output "function_names" {
  description = "Map of function name to the fully-qualified Lambda function name"
  value       = { for k, v in aws_lambda_function.this : k => v.function_name }
}

output "alias_arns" {
  description = "Map of function name to the live alias ARN"
  value       = { for k, v in aws_lambda_alias.live : k => v.arn }
}

output "published_versions" {
  description = "Map of function name to the currently published version number"
  value       = { for k, v in aws_lambda_function.this : k => v.version }
}

output "alias_invoke_arns" {
  description = "Map of function name to the live alias invoke ARN (use for API Gateway integration)"
  value       = { for k, v in aws_lambda_alias.live : k => v.invoke_arn }
}

output "role_arns" {
  description = "Map of function name to IAM role ARN"
  value       = { for k, v in aws_iam_role.lambda : k => v.arn }
}

output "security_group_ids" {
  description = "Security group IDs used by Lambda (pass to ElastiCache module)"
  value       = var.vpc_security_group_ids
}
