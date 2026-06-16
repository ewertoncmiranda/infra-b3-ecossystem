output "sqs_queue_urls" {
  description = "URLs de todas as filas SQS"
  value       = var.create_sqs ? module.sqs[0].queue_urls : {}
}

output "sqs_queue_arns" {
  description = "ARNs de todas as filas SQS"
  value       = var.create_sqs ? module.sqs[0].queue_arns : {}
}

output "s3_bucket_names" {
  description = "Nomes de todos os buckets S3"
  value       = var.create_s3 ? module.s3[0].bucket_names : {}
}

output "s3_bucket_arns" {
  description = "ARNs de todos os buckets S3"
  value       = var.create_s3 ? module.s3[0].bucket_arns : {}
}

output "s3_bucket_ids" {
  description = "IDs de todos os buckets S3"
  value       = var.create_s3 ? module.s3[0].bucket_ids : {}
}

output "infrastructure_summary" {
  description = "Resumo da infraestrutura criada"
  value = {
    environment = var.environment
    region      = var.aws_region
    sqs_enabled = var.create_sqs
    s3_enabled  = var.create_s3
    project     = var.project_name
  }
}

