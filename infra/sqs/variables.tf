variable "sqs_queues" {
  description = "Mapa de filas SQS a criar"
  type = map(object({
    name                      = string
    delay_seconds             = optional(number, 0)
    max_message_size          = optional(number, 262144)
    message_retention_seconds = optional(number, 86400)
    receive_wait_time_seconds = optional(number, 10)
  }))
}

variable "common_tags" {
  description = "Tags comuns para todos os recursos"
  type        = map(string)
}

variable "environment" {
  description = "Ambiente"
  type        = string
}

