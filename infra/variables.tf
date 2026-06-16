variable "aws_region" {
  description = "AWS region para LocalStack"
  type        = string
  default     = "sa-east-1"
}

variable "aws_endpoint" {
  description = "Endpoint do LocalStack"
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_access_key" {
  description = "Chave de acesso AWS"
  type        = string
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  description = "Chave secreta AWS"
  type        = string
  default     = "test"
  sensitive   = true
}

variable "environment" {
  description = "Ambiente de execução"
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "dev", "homolog", "prod"], var.environment)
    error_message = "Environment deve ser: local, dev, homolog ou prod."
  }
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "devops-b3-monitoring"
}

variable "create_sqs" {
  description = "Criar recursos SQS"
  type        = bool
  default     = true
}

variable "create_s3" {
  description = "Criar recursos S3"
  type        = bool
  default     = true
}

