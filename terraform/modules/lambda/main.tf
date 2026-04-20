# -----------------------------------------------------------------------------
# Lambda functions zip deployment on arm64
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  for_each = var.functions

  function_name    = "url-shortener-${each.key}-${var.environment}"
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = var.runtime
  architectures    = ["arm64"]
  handler          = each.value.handler
  filename         = each.value.zip_path
  source_code_hash = filebase64sha256(each.value.zip_path)
  memory_size      = each.value.memory_mb
  timeout          = each.value.timeout_seconds
  publish          = true

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  dynamic "vpc_config" {
    for_each = length(var.vpc_subnet_ids) > 0 ? [1] : []

    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  environment {
    variables = merge(each.value.environment, {
      ENVIRONMENT                  = var.environment
      LOG_LEVEL                    = "INFO"
      POWERTOOLS_SERVICE_NAME      = "url-shortener"
      POWERTOOLS_METRICS_NAMESPACE = "URLShortener"
    })
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# -----------------------------------------------------------------------------
# Live alias always points to the latest published version.
# Rollback: update the alias to a previous version number via CLI or Makefile or from console (mot recommended).
# API Gateway invokes the alias ARN, so rollback is instant (no redeploy).
# -----------------------------------------------------------------------------

resource "aws_lambda_alias" "live" {
  for_each = var.functions

  name             = "live"
  function_name    = aws_lambda_function.this[each.key].arn
  function_version = aws_lambda_function.this[each.key].version
}

# -----------------------------------------------------------------------------
# IAM Role for least privilege
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  for_each = var.functions

  name = "url-shortener-${each.key}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

# Attach AWS managed policy for basic execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "basic_execution" {
  for_each = var.functions

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC access policy when VPC is configured
resource "aws_iam_role_policy_attachment" "vpc_access" {
  for_each = length(var.vpc_subnet_ids) > 0 ? var.functions : {}

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# X-Ray tracing policy, default is disabled for cost reasons
resource "aws_iam_role_policy_attachment" "xray" {
  for_each = var.enable_xray_tracing ? var.functions : {}

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# DynamoDB access policy
resource "aws_iam_role_policy" "dynamodb" {
  for_each = var.functions

  name = "dynamodb-access"
  role = aws_iam_role.lambda[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
      ]
      Resource = [
        var.dynamodb_table_arn,
        "${var.dynamodb_table_arn}/index/*", # to query the GSI if needed
      ]
    }]
  })
}


