output "distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.arn
}

output "waf_acl_arn" {
  description = "ARN of the WAF WebACL (empty string if WAF is disabled)"
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : ""
}

