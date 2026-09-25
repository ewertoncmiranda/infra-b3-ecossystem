variable "sns_topics" {
  description = "Mapa de topicos SNS a criar"
  type = map(object({
    name         = string
    display_name = optional(string)
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
