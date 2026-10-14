resource "aws_sqs_queue" "dlqs" {
  for_each = var.sqs_queues

  name                      = "${each.value.name}-dlq"
  message_retention_seconds = 1209600

  tags = merge(
    var.common_tags,
    {
      Component = "DeadLetterQueue"
      QueueName = each.key
    }
  )
}

resource "aws_sqs_queue" "queues" {
  for_each = var.sqs_queues

  name                       = each.value.name
  delay_seconds              = each.value.delay_seconds
  max_message_size           = each.value.max_message_size
  message_retention_seconds  = each.value.message_retention_seconds
  receive_wait_time_seconds  = each.value.receive_wait_time_seconds
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlqs[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })

  tags = merge(
    var.common_tags,
    {
      Component = "Queue"
      QueueName = each.key
    }
  )
}

