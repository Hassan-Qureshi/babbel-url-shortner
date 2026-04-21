variable "functions" {
  description = "Map of Lambda function configurations keyed by function name"
  type = map(object({
    handler         = string
    zip_path        = string
    memory_mb       = optional(number, 256)
    timeout_seconds = optional(number, 10)
    environment     = optional(map(string), {})
  }))
}

variable "runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.13"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray active tracing on Lambda functions"
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "Subnet IDs for Lambda VPC configuration (required for Redis access)"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Security group IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table the Lambdas need access to"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}

