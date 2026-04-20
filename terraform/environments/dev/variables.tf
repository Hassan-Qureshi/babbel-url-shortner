variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
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


variable "alarm_email" {
  description = "Email address to receive alarm notifications"
  type        = string
  default     = ""
}

variable "base_url" {
  description = "Base URL for shortened links (e.g. https://short.example.com). Set to the CloudFront domain after first deploy."
  type        = string
  default     = "https://localhost"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}


