# -----------------------------------------------------------------------------
# SNS Topic for alarm notifications
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  count = var.enable_alarms ? 1 : 0

  name = "url-shortener-alarms-${var.environment}"

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.enable_alarms && var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -----------------------------------------------------------------------------
# Lambda error alarms, one per function
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.enable_alarms ? var.lambda_function_names : {}

  alarm_name          = "url-shortener-${each.key}-errors-${var.environment}"
  alarm_description   = "Lambda ${each.key} error count exceeded threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = var.enable_alarms ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.enable_alarms ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# Lambda p99 latency alarms, one per function
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "lambda_latency" {
  for_each = var.enable_alarms ? var.lambda_function_names : {}

  alarm_name          = "url-shortener-${each.key}-p99-latency-${var.environment}"
  alarm_description   = "Lambda ${each.key} p99 latency exceeded ${var.lambda_p99_latency_threshold_ms}ms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p99"
  threshold           = var.lambda_p99_latency_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = var.enable_alarms ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# DynamoDB throttle alarm
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "url-shortener-dynamodb-throttles-${var.environment}"
  alarm_description   = "DynamoDB read/write throttle events detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "read_throttles"
    return_data = false

    metric {
      metric_name = "ReadThrottleEvents"
      namespace   = "AWS/DynamoDB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        TableName = var.dynamodb_table_name
      }
    }
  }

  metric_query {
    id          = "write_throttles"
    return_data = false

    metric {
      metric_name = "WriteThrottleEvents"
      namespace   = "AWS/DynamoDB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        TableName = var.dynamodb_table_name
      }
    }
  }

  metric_query {
    id          = "total_throttles"
    expression  = "read_throttles + write_throttles"
    label       = "Total Throttle Events"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "url-shortener-${var.environment}"

  dashboard_body = jsonencode({
    widgets = concat(
      # Lambda invocations + errors per function
      [for name, fn_name in var.lambda_function_names : {
        type   = "metric"
        x      = name == "shorten" ? 0 : 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "${name} — Invocations & Errors"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", fn_name, { stat = "Sum" }],
            ["AWS/Lambda", "Errors", "FunctionName", fn_name, { stat = "Sum", color = "#d62728" }],
          ]
          period = 300
          region = "eu-central-1"
          view   = "timeSeries"
        }
      }],
      # Lambda duration per function
      [for name, fn_name in var.lambda_function_names : {
        type   = "metric"
        x      = name == "shorten" ? 0 : 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "${name} — Duration"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", fn_name, { stat = "p50" }],
            ["AWS/Lambda", "Duration", "FunctionName", fn_name, { stat = "p99", color = "#d62728" }],
          ]
          period = 300
          region = "eu-central-1"
          view   = "timeSeries"
        }
      }],
      # Custom metrics — cache hits/misses + URLs created
      [{
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "Cache Hit / Miss"
          metrics = [
            ["URLShortener", "CacheHit", { stat = "Sum" }],
            ["URLShortener", "CacheMiss", { stat = "Sum", color = "#d62728" }],
          ]
          period = 300
          region = "eu-central-1"
          view   = "timeSeries"
        }
      }],
      [{
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "URLs Created"
          metrics = [
            ["URLShortener", "URLsCreated", { stat = "Sum" }],
          ]
          period = 300
          region = "eu-central-1"
          view   = "timeSeries"
        }
      }],
      # Cold starts
      [{
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title = "Cold Starts"
          metrics = [
            ["URLShortener", "ColdStart", { stat = "Sum" }],
          ]
          period = 300
          region = "eu-central-1"
          view   = "timeSeries"
        }
      }],
      # DynamoDB
      [{
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title = "DynamoDB — Consumed Capacity & Throttles"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name, { stat = "Sum" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_table_name, { stat = "Sum" }],
            ["AWS/DynamoDB", "ReadThrottleEvents", "TableName", var.dynamodb_table_name, { stat = "Sum", color = "#d62728" }],
            ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", var.dynamodb_table_name, { stat = "Sum", color = "#ff7f0e" }],
          ]
          period = 300
          region = "eu-central-1"
          view   = "timeSeries"
        }
      }],
    )
  })
}

