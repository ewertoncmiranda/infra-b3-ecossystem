output "queue_urls" {
  description = "URLs das filas SQS criadas"
  value = {
    for key, queue in aws_sqs_queue.queues : key => queue.url
  }
}

output "queue_arns" {
  description = "ARNs das filas SQS criadas"
  value = {
    for key, queue in aws_sqs_queue.queues : key => queue.arn
  }
}

