variable "environment" {
  description = "Deployment environmnt (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "api_gateway_domain" {
  description = "Domain name of the API Gateway endpoint (without protocol)"
  type        = string
}

variable "api_gateway_stage" {
  description = "API Gateway stage name used as origin path"
  type        = string
}

variable "custom_domain" {
  description = "Custom domain name for CloudFront (optional)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the custom domain (must be in us-east-1 CloudFront requirement)"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Whether to attach a WAF WebACL to the CloudFront distribution"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute window per IP before rate-limiting kicks in"
  type        = number
  default     = 2000
}

variable "waf_blocked_countries" {
  description = "List of ISO 3166-1 alpha-2 country codes to geo-block"
  type        = list(string)
  default     = []
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Additional tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}

