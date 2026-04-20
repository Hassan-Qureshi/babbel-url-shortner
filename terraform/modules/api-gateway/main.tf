# -----------------------------------------------------------------------------
# REST API
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.api_name}-${var.environment}"
  description = "URL shortener REST API ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# POST /shorten
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "shorten" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "shorten"
}

resource "aws_api_gateway_method" "shorten_post" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.shorten.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "shorten_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.shorten.id
  http_method             = aws_api_gateway_method.shorten_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.shorten_lambda_invoke_arn
}

# -----------------------------------------------------------------------------
# GET /{code}
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "redirect" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{code}"
}

resource "aws_api_gateway_method" "redirect_get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.code" = true
  }
}

resource "aws_api_gateway_integration" "redirect_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.redirect.id
  http_method             = aws_api_gateway_method.redirect_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.redirect_lambda_invoke_arn
}

# -----------------------------------------------------------------------------
# Deployment + Stage
# -----------------------------------------------------------------------------

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.shorten.id,
      aws_api_gateway_method.shorten_post.id,
      aws_api_gateway_method.shorten_post.api_key_required,
      aws_api_gateway_integration.shorten_post.id,
      aws_api_gateway_resource.redirect.id,
      aws_api_gateway_method.redirect_get.id,
      aws_api_gateway_integration.redirect_get.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.environment

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.throttle_burst_limit
    throttling_rate_limit  = var.throttle_rate_limit
    metrics_enabled        = true
    logging_level          = "OFF" # for now its is not needed since we already have logging in Lambda, and it can be costly at scale. We can enable it later if needed.
  }
}

# -----------------------------------------------------------------------------
# Lambda permissions allow API Gateway to invoke each function
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "shorten" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.shorten_lambda_function_name
  qualifier     = "live"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "redirect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.redirect_lambda_function_name
  qualifier     = "live"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# API Key + Usage Plan POST /shorten requires x-api-key header
# GET /{code} remains public (no key needed)
# -----------------------------------------------------------------------------

resource "aws_api_gateway_api_key" "this" {
  name    = "url-shortener-${var.environment}"
  enabled = true

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "url-shortener-${var.environment}"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  throttle_settings {
    burst_limit = var.throttle_burst_limit
    rate_limit  = var.throttle_rate_limit
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}
