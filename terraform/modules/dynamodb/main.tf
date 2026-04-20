resource "aws_dynamodb_table" "this" {
  name         = "${var.table_name_prefix}-${var.environment}"
  billing_mode = var.billing_mode
  hash_key     = "code"

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  attribute {
    name = "code"
    type = "S"
  }

  attribute {
    name = "created_by"
    type = "S"
  }

  global_secondary_index {
    name            = "created-by-index"
    hash_key        = "created_by"
    projection_type = "ALL"
    read_capacity   = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
    write_capacity  = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "url-shortener"
    ManagedBy   = "terraform"
  })

  lifecycle {
    prevent_destroy = false
  }
}

