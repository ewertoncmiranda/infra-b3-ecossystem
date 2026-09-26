module "sqs" {
  count  = var.create_sqs ? 1 : 0
  source = "./sqs"

  sqs_queues = {
    tratar_ativos = {
      name                       = "tratar-ativos"
      delay_seconds              = local.sqs_config.delay_seconds
      max_message_size           = local.sqs_config.max_message_size
      message_retention_seconds  = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds  = local.sqs_config.receive_wait_time_seconds
      visibility_timeout_seconds = local.sqs_config.visibility_timeout_seconds
      max_receive_count          = local.sqs_config.max_receive_count
    }
    iniciar_treinamento = {
      name                       = "sqs-iniciar-treinamento"
      delay_seconds              = local.sqs_config.delay_seconds
      max_message_size           = local.sqs_config.max_message_size
      message_retention_seconds  = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds  = local.sqs_config.receive_wait_time_seconds
      visibility_timeout_seconds = local.sqs_config.visibility_timeout_seconds
      max_receive_count          = local.sqs_config.max_receive_count
    }
    registrar_series_historicas = {
      name                       = "sqs-registrar-series-historicas"
      delay_seconds              = local.sqs_config.delay_seconds
      max_message_size           = local.sqs_config.max_message_size
      message_retention_seconds  = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds  = local.sqs_config.receive_wait_time_seconds
      visibility_timeout_seconds = local.sqs_config.visibility_timeout_seconds
      max_receive_count          = local.sqs_config.max_receive_count
    }
    # Publicada pelo etl-fundamentos-cvm ao concluir uma carga; sinaliza ao
    # gerar-insights quais simbolos tiveram fundamentos atualizados.
    fundamentos_atualizados = {
      name                       = "sqs-fundamentos-atualizados"
      delay_seconds              = local.sqs_config.delay_seconds
      max_message_size           = local.sqs_config.max_message_size
      message_retention_seconds  = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds  = local.sqs_config.receive_wait_time_seconds
      visibility_timeout_seconds = local.sqs_config.visibility_timeout_seconds
      max_receive_count          = local.sqs_config.max_receive_count
    }
    # Publicada pelo etl-fundamentos-cvm (`--comunicados`) quando entram
    # comunicados novos da base IPE da CVM. Ainda sem consumidor: prepara a
    # analise com IA e integracoes futuras (contrato CTR-09).
    comunicados_publicados = {
      name                       = "sqs-comunicados-publicados"
      delay_seconds              = local.sqs_config.delay_seconds
      max_message_size           = local.sqs_config.max_message_size
      message_retention_seconds  = local.sqs_config.message_retention_seconds
      receive_wait_time_seconds  = local.sqs_config.receive_wait_time_seconds
      visibility_timeout_seconds = local.sqs_config.visibility_timeout_seconds
      max_receive_count          = local.sqs_config.max_receive_count
    }
  }

  common_tags = local.common_tags
  environment = var.environment

  depends_on = []
}

module "s3" {
  count  = var.create_s3 ? 1 : 0
  source = "./s3"

  s3_buckets = {
    salvar_insights = {
      name          = "bucket-salvar-insights"
      force_destroy = local.s3_config.force_destroy
      versioning    = local.s3_config.versioning
      block_public  = local.s3_config.block_public
    }
  }

  common_tags = local.common_tags
  environment = var.environment

  depends_on = []
}

module "sns" {
  count  = var.create_sns ? 1 : 0
  source = "./sns"

  sns_topics = {
    transmitir_lote_dados = {
      name         = "transmitir-lote-dados"
      display_name = "Transmitir lote de dados"
    }
  }

  common_tags = local.common_tags
  environment = var.environment

  depends_on = []
}
