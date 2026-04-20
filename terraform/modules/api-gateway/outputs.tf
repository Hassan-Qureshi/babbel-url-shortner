output "api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_endpoint" {
  description = "Invoke URL of the deployed API stage"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "execution_arn" {
  description = "Execution ARN of the REST API"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "stage_name" {
  description = "Name of the deployed stage"
  value       = aws_api_gateway_stage.this.stage_name
}

