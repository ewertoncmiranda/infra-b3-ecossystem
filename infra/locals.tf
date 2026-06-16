locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }

  naming_convention = {
    sqs_prefix = "sqs"
    s3_prefix  = "bucket"
    separator  = "-"
  }

  sqs_config = {
    delay_seconds             = 0
    max_message_size          = 262144
    message_retention_seconds = 86400
    receive_wait_time_seconds = 10
  }

  s3_config = {
    force_destroy = true
    versioning    = "Disabled"
    block_public  = true
  }
}

