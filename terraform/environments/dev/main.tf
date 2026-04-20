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

# CloudFront WAF AWS hard requirement: CloudFront MUST be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# DynamoDB
# -----------------------------------------------------------------------------

module "dynamodb" {
  source = "../../modules/dynamodb"

  environment  = var.environment
  billing_mode = "PAY_PER_REQUEST"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ElastiCache Redis
# -----------------------------------------------------------------------------

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

# module "elasticache" {
#   source = "../../modules/elasticache"
#
#   environment                = var.environment
#   vpc_id                     = local.vpc_id
#   subnet_ids                 = local.private_subnet_ids
#   allowed_security_group_ids = [aws_security_group.lambda.id]
#   node_type                  = "cache.t4g.micro"
#   num_cache_nodes            = 1
#   snapshot_retention_limit   = 0
#
#   tags = var.tags
# }

# -----------------------------------------------------------------------------
# Lambda functions
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
      memory_mb       = 256
      timeout_seconds = 10
      environment = {
        DYNAMODB_TABLE = module.dynamodb.table_name
        # REDIS_ENDPOINT = module.elasticache.primary_endpoint
        BASE_URL       = var.base_url
      }
    }
    redirect = {
      handler         = "redirect.handler.handler"
      zip_path        = var.redirect_zip_path
      memory_mb       = 256
      timeout_seconds = 5
      environment = {
        DYNAMODB_TABLE = module.dynamodb.table_name
        # REDIS_ENDPOINT = module.elasticache.primary_endpoint
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
  throttle_burst_limit          = 100
  throttle_rate_limit           = 50

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudFront + WAF
# -----------------------------------------------------------------------------

module "cloudfront" {
  source = "../../modules/cloudfront-waf"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment        = var.environment
  # Remove protocol and stage from API Gateway endpoint to get the base domain for CloudFront
  api_gateway_domain = replace(replace(module.api_gateway.api_endpoint, "/^https?:\\/\\//", ""), "/${var.environment}", "")
  api_gateway_stage  = var.environment
  enable_waf         = false
  waf_rate_limit     = 2000

  tags = var.tags
}




