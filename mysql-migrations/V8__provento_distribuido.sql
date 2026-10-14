-- Cache de proventos (dividendo/JCP) por emissora, lido da B3
-- (GetListedSupplementCompany, endpoint publico sem chave, confirmado ao
-- vivo em 27/09/2026) por ServicoAtualizacaoProventos no gestor-ativos-brutos.
--
-- So os ultimos 12 meses vem em cada consulta (limite da propria B3): a
-- tabela acumula historico real a partir de agora, rodando 1x/dia - nao e
-- backfill de anos anteriores (isso continua em aberto para o backtest do
-- gerar-insights usar retorno com proventos).
CREATE TABLE IF NOT EXISTS provento_distribuido (
    id                       BIGINT         NOT NULL AUTO_INCREMENT,
    -- Codigo de 4 letras do emissor (PETR), nao o ticker com o digito da
    -- especie - PETR3 e PETR4 sao a mesma emissora e o mesmo provento (por
    -- classe de acao, distinguido pelo isin).
    simbolo                  VARCHAR(10)    NOT NULL,
    isin                     VARCHAR(20)    NOT NULL,
    tipo                     VARCHAR(30)    NOT NULL,
    valor_por_acao           DECIMAL(14,8)  NOT NULL,
    periodo_referencia       VARCHAR(30)    NULL,
    aprovado_em              DATE           NULL,
    ultima_data_com_direito  DATE           NULL,
    data_pagamento           DATE           NOT NULL,
    atualizado_em            DATETIME(6)    NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_provento_distribuido (simbolo, isin, tipo, data_pagamento),
    INDEX idx_provento_distribuido_simbolo (simbolo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
