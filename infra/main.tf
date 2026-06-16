module "sqs" {
  count   = var.create_sqs ? 1 : 0
  source  = "./sqs"

  sqs_queues = {
    tratar_ativos = {
      name                      = "tratar-ativos"
      delay_seconds             = local.sqs_config.delay_seconds
      max_message_size          = local.sqs_config.max_message_size
      message_retention_seconds = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds = local.sqs_config.receive_wait_time_seconds
    }
    iniciar_treinamento = {
      name                      = "sqs-iniciar-treinamento"
      delay_seconds             = local.sqs_config.delay_seconds
      max_message_size          = local.sqs_config.max_message_size
      message_retention_seconds = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds = local.sqs_config.receive_wait_time_seconds
    }
  }

  common_tags = local.common_tags
  environment = var.environment

  depends_on = []
}

module "s3" {
  count   = var.create_s3 ? 1 : 0
  source  = "./s3"

  s3_buckets = {
    salvar_insights = {
      name           = "bucket-salvar-insights"
      force_destroy  = local.s3_config.force_destroy
      versioning     = local.s3_config.versioning
      block_public   = local.s3_config.block_public
    }
  }

  common_tags = local.common_tags
  environment = var.environment

  depends_on = []
}