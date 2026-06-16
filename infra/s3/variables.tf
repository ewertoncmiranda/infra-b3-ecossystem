variable "s3_buckets" {
  description = "Mapa de buckets S3 a criar"
  type = map(object({
    name           = string
    force_destroy  = optional(bool, true)
    versioning     = optional(string, "Disabled")
    block_public   = optional(bool, true)
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

