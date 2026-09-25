resource "aws_sns_topic" "topics" {
  for_each = var.sns_topics

  name         = each.value.name
  display_name = each.value.display_name

  tags = merge(
    var.common_tags,
    {
      Component = "Notification"
      TopicName = each.key
    }
  )
}
