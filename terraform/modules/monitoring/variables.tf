variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "lambda_function_names" {
  description = "Map of Lambda function names to monitor (e.g. {shorten = 'url-shortener-shorten-dev'})"
  type        = map(string)
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table to monitor"
  type        = string
}

variable "alarm_email" {
  description = "Email address to receive alarm notifications"
  type        = string
  default     = ""
}

variable "enable_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "lambda_error_threshold" {
  description = "Number of Lambda errors in a 5-minute period before alarm fires"
  type        = number
  default     = 5
}

variable "lambda_p99_latency_threshold_ms" {
  description = "Lambda p99 latency threshold in milliseconds"
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Additional tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}

