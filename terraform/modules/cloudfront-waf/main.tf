# -----------------------------------------------------------------------------
# WAF rate limiting + optional geo-blocking + AWS managed rules
# WAF for CloudFront MUST be in us-east-1 (AWS hard requirementn regardless of deployment region).
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0

  provider = aws.us_east_1

  name        = "url-shortener-${var.environment}"
  description = "WAF for URL shortener CloudFront ${var.environment}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate limiting
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "url-shortener-rate-limit-${var.environment}"
    }
  }

  # AWS managed common rule set
  rule {
    name     = "aws-common-rules"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "url-shortener-common-rules-${var.environment}"
    }
  }

  # AWS managed IP reputation list
  rule {
    name     = "aws-ip-reputation"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "url-shortener-ip-reputation-${var.environment}"
    }
  }

  # Optional geo-blocking
  dynamic "rule" {
    for_each = length(var.waf_blocked_countries) > 0 ? [1] : []

    content {
      name     = "geo-block"
      priority = 4

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.waf_blocked_countries
        }
      }

      visibility_config {
        sampled_requests_enabled   = true
        cloudwatch_metrics_enabled = true
        metric_name                = "url-shortener-geo-block-${var.environment}"
      }
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "url-shortener-waf-${var.environment}"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# CloudFront distribution
# -----------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "URL shortener ${var.environment}"
  price_class     = var.price_class
  web_acl_id      = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null

  aliases = var.custom_domain != "" ? [var.custom_domain] : []

  origin {
    domain_name = var.api_gateway_domain
    origin_id   = "api-gateway"
    origin_path = "/${var.api_gateway_stage}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "api-gateway"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 60
  }

  # Cache redirects (GET /{code}) at the edge
  ordered_cache_behavior {
    path_pattern           = "/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "api-gateway"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 60
    max_ttl     = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

