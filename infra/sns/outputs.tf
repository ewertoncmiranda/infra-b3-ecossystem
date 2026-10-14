output "topic_arns" {
  description = "ARNs de todos os topicos SNS"
  value = {
    for key, topic in aws_sns_topic.topics : key => topic.arn
  }
}

output "topic_names" {
  description = "Nomes de todos os topicos SNS"
  value = {
    for key, topic in aws_sns_topic.topics : key => topic.name
  }
}

output "topic_ids" {
  description = "IDs de todos os topicos SNS"
  value = {
    for key, topic in aws_sns_topic.topics : key => topic.id
  }
}
