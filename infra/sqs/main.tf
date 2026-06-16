resource "aws_sqs_queue" "queues" {
  for_each = var.sqs_queues

  name                      = each.value.name
  delay_seconds             = each.value.delay_seconds
  max_message_size          = each.value.max_message_size
  message_retention_seconds = each.value.message_retention_seconds
  receive_wait_time_seconds = each.value.receive_wait_time_seconds

  tags = merge(
    var.common_tags,
    {
      Component = "Queue"
      QueueName = each.key
    }
  )
}

