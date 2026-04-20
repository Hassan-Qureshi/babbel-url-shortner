variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "api_name" {
  description = "Name of the REST API"
  type        = string
  default     = "url-shortener"
}

variable "shorten_lambda_invoke_arn" {
  description = "Invoke ARN of the shorten Lambda function"
  type        = string
}

variable "redirect_lambda_invoke_arn" {
  description = "Invoke ARN of the redirect Lambda function"
  type        = string
}

variable "shorten_lambda_function_name" {
  description = "Function name of the shorten Lambda (used for permission)"
  type        = string
}

variable "redirect_lambda_function_name" {
  description = "Function name of the redirect Lambda (used for permission)"
  type        = string
}

variable "throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 100
}

variable "throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Additional tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}

