terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "sa-east-1"
}

variable "aws_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  s3_use_path_style            = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = var.aws_endpoint
    sqs = var.aws_endpoint
  }
}

resource "aws_sqs_queue" "tratar_ativos" {
  name                      = "tratar-ativos"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10

  tags = {
    Environment = "local"
    Project     = "devops-b3-monitoring"
  }
}

resource "aws_sqs_queue" "iniciar_treinamento" {
  name                      = "sqs-iniciar-treinamento"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10

  tags = {
    Environment = "local"
    Project     = "devops-b3-monitoring"
  }
}

resource "aws_s3_bucket" "salvar_insights" {
  bucket        = "bucket-salvar-insights"
  force_destroy = true

  tags = {
    Environment = "local"
    Project     = "devops-b3-monitoring"
  }
}

resource "aws_s3_bucket_versioning" "salvar_insights" {
  bucket = aws_s3_bucket.salvar_insights.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "salvar_insights" {
  bucket = aws_s3_bucket.salvar_insights.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value = aws_s3_bucket.salvar_insights.bucket
}

output "tratar_ativos_queue_url" {
  value = aws_sqs_queue.tratar_ativos.url
}

output "iniciar_treinamento_queue_url" {
  value = aws_sqs_queue.iniciar_treinamento.url
}