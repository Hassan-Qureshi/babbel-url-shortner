variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "shorten_zip_path" {
  description = "Path to the shorten Lambda deployment zip"
  type        = string
  default     = "../../../lambda/dist/shorten.zip"
}

variable "redirect_zip_path" {
  description = "Path to the redirect Lambda deployment zip"
  type        = string
  default     = "../../../lambda/dist/redirect.zip"
}


variable "custom_domain" {
  description = "Custom short domain (e.g. sca.la)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for custom domain (must be in us-east-1 CloudFront requirement)"
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "Email address to receive alarm notifications"
  type        = string
}

variable "base_url" {
  description = "Base URL for shortened links (e.g. https://sca.la). Set to CloudFront domain or custom domain."
  type        = string
}

variable "waf_blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to geo-block"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}


