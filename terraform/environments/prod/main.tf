provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "url-shortener"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# DynamoDB production uses PITR and prevent_destroy
# -----------------------------------------------------------------------------

module "dynamodb" {
  source = "../../modules/dynamodb"

  environment                   = var.environment
  billing_mode                  = "PAY_PER_REQUEST"
  enable_point_in_time_recovery = true

  tags = var.tags
}

resource "aws_security_group" "lambda" {
  name_prefix = "url-shortener-lambda-${var.environment}-"
  description = "Security group for URL shortener Lambda functions"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Lambda functions production: more memory
# -----------------------------------------------------------------------------

module "lambda" {
  source = "../../modules/lambda"

  environment            = var.environment
  dynamodb_table_arn     = module.dynamodb.table_arn
  vpc_subnet_ids         = local.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda.id]

  functions = {
    shorten = {
      handler         = "shorten.handler.handler"
      zip_path        = var.shorten_zip_path
      memory_mb       = 1024
      timeout_seconds = 10
      environment = {
        DYNAMODB_TABLE = module.dynamodb.table_name
        BASE_URL       = var.base_url
      }
    }
    redirect = {
      handler         = "redirect.handler.handler"
      zip_path        = var.redirect_zip_path
      memory_mb       = 1024
      timeout_seconds = 5
      environment = {
        DYNAMODB_TABLE = module.dynamodb.table_name
        BASE_URL       = var.base_url
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# API Gateway
# -----------------------------------------------------------------------------

module "api_gateway" {
  source = "../../modules/api-gateway"

  environment                   = var.environment
  shorten_lambda_invoke_arn     = module.lambda.alias_invoke_arns["shorten"]
  redirect_lambda_invoke_arn    = module.lambda.alias_invoke_arns["redirect"]
  shorten_lambda_function_name  = module.lambda.function_names["shorten"]
  redirect_lambda_function_name = module.lambda.function_names["redirect"]
  throttle_burst_limit          = 500
  throttle_rate_limit           = 200

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudFront + WAF production: full WAF, optional custom domain + geo-block
# -----------------------------------------------------------------------------

module "cloudfront" {
  source = "../../modules/cloudfront-waf"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment              = var.environment
  api_gateway_domain       = replace(replace(module.api_gateway.api_endpoint, "/^https?:\\/\\//", ""), "/${var.environment}", "")
  api_gateway_stage        = var.environment
  enable_waf               = true
  enable_waf_common_rules  = true
  enable_waf_ip_reputation = true
  waf_rate_limit           = 5000
  waf_blocked_countries    = var.waf_blocked_countries
  custom_domain            = var.custom_domain
  acm_certificate_arn      = var.acm_certificate_arn
  price_class              = "PriceClass_All"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Monitoring production: full alarms
# -----------------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  environment                     = var.environment
  lambda_function_names           = module.lambda.function_names
  dynamodb_table_name             = module.dynamodb.table_name
  enable_alarms                   = true
  alarm_email                     = var.alarm_email
  lambda_error_threshold          = 3
  lambda_p99_latency_threshold_ms = 500

  tags = var.tags
}

