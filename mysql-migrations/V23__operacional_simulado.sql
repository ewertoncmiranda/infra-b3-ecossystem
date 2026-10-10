-- Plano OPR (OPR-INFRA-1, DEC-OPR-1 de 2026-10-10): sistema operavel em MODO SIMULADO (paper trading).
-- Nenhuma linha daqui e ordem, recomendacao de investimento ou autorizacao para capital real.
--
-- Escritores (uma tabela, um escritor):
--   ativo_liquidez_diaria  -> etl-fundamentos-cvm (OPR-ETL-1..3), so metricas brutas do COTAHIST
--   regra_operacional      -> esta migration (versao inicial) e migrations futuras; versao em uso nao se edita
--   operacao_simulada      -> gerar-insights (OPR-INS-2..5)
--   diario_operacional     -> gerar-insights (OPR-INS-4..6)
--   evento_operacional     -> gerar-insights (OPR-INS-7); gestor e painel so leem
-- Leitores: gestor (somente leitura) -> painel por HTTP.
--
-- Ausente e NULL com motivo (motivos_ausencia_json), nunca 0. Valores em R$ com DECIMAL; fracoes
-- (retornos, spread, percentis) em DECIMAL(12,8), ex.: 0.0052 = 0,52%.

-- --------------------------------------------------------------------------------------------
-- Liquidez e microestrutura por ativo e pregao (metricas da secao "Metricas fixadas" do SPEC do
-- ETL). Calculadas so com pregoes ate data_pregao (inclusive): sem olhar o futuro.
-- A faixa ALTA/MEDIA/INSUFICIENTE NAO mora aqui: e decisao do gerar-insights por versao de regra.
CREATE TABLE IF NOT EXISTS ativo_liquidez_diaria (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(12) NOT NULL,
    data_pregao DATE NOT NULL,

    volume_financeiro_medio_21d DECIMAL(20,2) NULL,
    volume_financeiro_medio_63d DECIMAL(20,2) NULL,
    negocios_medio_63d DECIMAL(14,2) NULL,
    presenca_63d DECIMAL(12,8) NULL,          -- fracao dos ultimos 63 pregoes do mercado com negocio
    spread_mediano_63d DECIMAL(12,8) NULL,    -- (melhor venda - melhor compra) / preco medio
    atr14 DECIMAL(18,6) NULL,                 -- R$, true range medio de 14 pregoes, preco bruto
    volatilidade_63d DECIMAL(12,8) NULL,      -- desvio-padrao dos retornos log, anualizado (raiz de 252)
    percentil_volatilidade DECIMAL(12,8) NULL,-- no universo do mesmo pregao
    dias_sem_preco_63d SMALLINT NULL,
    ajuste_serie VARCHAR(25) NOT NULL DEFAULT 'BRUTA',

    -- {"coluna": "motivo"} para cada metrica NULL (ex.: historico menor que 63 pregoes)
    motivos_ausencia_json JSON NULL,
    versao_calculo VARCHAR(30) NOT NULL,
    schema_version VARCHAR(10) NOT NULL DEFAULT '1',

    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_ativo_liquidez_diaria UNIQUE (simbolo, data_pregao),
    CONSTRAINT ck_liquidez_ajuste_serie CHECK (ajuste_serie IN ('BRUTA','AJUSTADA_EVENTO','AJUSTE_INDISPONIVEL')),
    INDEX idx_liquidez_pregao (data_pregao)
);

-- --------------------------------------------------------------------------------------------
-- Versoes da regra operacional: elegibilidade, sizing, saida, custos e IR num JSON por versao.
-- Mudar qualquer numero = versao nova; a versao ATIVA nunca e editada (o diario fica comparavel).
CREATE TABLE IF NOT EXISTS regra_operacional (
    id INT AUTO_INCREMENT PRIMARY KEY,

    versao_regra VARCHAR(30) NOT NULL,
    descricao VARCHAR(500) NOT NULL,
    parametros_json JSON NOT NULL,
    regras_ir_versao VARCHAR(30) NOT NULL,    -- arquivo de regras fiscais (OPERACIONAL_REGRAS_IR)
    vigente_desde DATE NOT NULL,
    status VARCHAR(12) NOT NULL DEFAULT 'RASCUNHO',
    schema_version VARCHAR(10) NOT NULL DEFAULT '1',

    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_regra_operacional_versao UNIQUE (versao_regra),
    CONSTRAINT ck_regra_operacional_status CHECK (status IN ('RASCUNHO','ATIVA','ENCERRADA'))
);

-- --------------------------------------------------------------------------------------------
-- Uma operacao simulada: decisao no fechamento de D, execucao simulada na abertura de D+1.
-- Abre ABERTA (ou PENDENTE ate o D+1 existir); fecha com um unico motivo, pela prioridade da regra.
CREATE TABLE IF NOT EXISTS operacao_simulada (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    versao_regra VARCHAR(30) NOT NULL,
    simbolo VARCHAR(12) NOT NULL,
    setor_grupo VARCHAR(60) NULL,
    horizonte_pregoes SMALLINT NOT NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'PENDENTE',

    -- entrada
    data_decisao_entrada DATE NOT NULL,
    data_entrada DATE NULL,
    preco_entrada DECIMAL(18,6) NULL,
    quantidade INT NULL,
    valor_entrada DECIMAL(20,2) NULL,
    atr_entrada DECIMAL(18,6) NULL,
    stop_inicial DECIMAL(18,6) NULL,
    stop_atual DECIMAL(18,6) NULL,
    maxima_desde_entrada DECIMAL(18,6) NULL,
    faixa_liquidez_entrada VARCHAR(15) NULL,
    motivo_entrada_json JSON NOT NULL,         -- sinal, opiniao, elegibilidade e calculo do tamanho

    -- saida
    data_decisao_saida DATE NULL,
    data_saida DATE NULL,
    preco_saida DECIMAL(18,6) NULL,
    motivo_saida VARCHAR(12) NULL,
    motivo_saida_json JSON NULL,

    -- resultado (R$); imposto e estimativa apurada por mes, rateada para a operacao
    custos_entrada DECIMAL(18,2) NULL,
    custos_saida DECIMAL(18,2) NULL,
    resultado_bruto DECIMAL(20,2) NULL,
    resultado_pos_custos DECIMAL(20,2) NULL,
    imposto_estimado DECIMAL(18,2) NULL,
    resultado_pos_imposto_estimado DECIMAL(20,2) NULL,

    schema_version VARCHAR(10) NOT NULL DEFAULT '1',
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- rodar o mesmo pregao duas vezes nao abre a mesma operacao de novo
    CONSTRAINT uq_operacao_simulada UNIQUE (versao_regra, simbolo, horizonte_pregoes, data_decisao_entrada),
    CONSTRAINT fk_operacao_regra FOREIGN KEY (versao_regra) REFERENCES regra_operacional (versao_regra),
    CONSTRAINT ck_operacao_status CHECK (status IN ('PENDENTE','ABERTA','FECHADA','CANCELADA')),
    CONSTRAINT ck_operacao_faixa CHECK (faixa_liquidez_entrada IS NULL
        OR faixa_liquidez_entrada IN ('ALTA','MEDIA','INSUFICIENTE')),
    CONSTRAINT ck_operacao_motivo_saida CHECK (motivo_saida IS NULL
        OR motivo_saida IN ('EVENTO','STOP','LIQUIDEZ','SINAL','PRAZO')),
    CONSTRAINT ck_operacao_horizonte CHECK (horizonte_pregoes > 0),
    INDEX idx_operacao_status (versao_regra, status),
    INDEX idx_operacao_ativo (simbolo, data_decisao_entrada)
);

-- --------------------------------------------------------------------------------------------
-- Fotografia diaria da carteira simulada. Benchmark justo = CDI LIQUIDO de IR (tabela regressiva
-- da renda fixa), alem do CDI bruto (DEC-OPR-1).
CREATE TABLE IF NOT EXISTS diario_operacional (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    versao_regra VARCHAR(30) NOT NULL,
    data_pregao DATE NOT NULL,

    capital_inicial DECIMAL(20,2) NOT NULL,
    patrimonio DECIMAL(20,2) NOT NULL,
    caixa DECIMAL(20,2) NOT NULL,
    exposicao DECIMAL(12,8) NOT NULL,          -- fracao do patrimonio em posicoes
    posicoes_abertas SMALLINT NOT NULL DEFAULT 0,
    operacoes_abertas_dia SMALLINT NOT NULL DEFAULT 0,
    operacoes_fechadas_dia SMALLINT NOT NULL DEFAULT 0,

    retorno_bruto_dia DECIMAL(12,8) NULL,
    retorno_liquido_dia DECIMAL(12,8) NULL,    -- depois de custos e imposto estimado
    retorno_liquido_acumulado DECIMAL(12,8) NULL,
    cdi_dia DECIMAL(12,8) NULL,
    cdi_acumulado DECIMAL(12,8) NULL,
    cdi_liquido_ir_acumulado DECIMAL(12,8) NULL,
    excesso_sobre_cdi_liquido DECIMAL(12,8) NULL,
    drawdown DECIMAL(12,8) NULL,
    drawdown_maximo DECIMAL(12,8) NULL,
    imposto_estimado_mes DECIMAL(18,2) NULL,
    violacoes_liquidez SMALLINT NOT NULL DEFAULT 0,

    status_sistema VARCHAR(25) NOT NULL DEFAULT 'NAO_OPERAVEL',
    motivos_status_json JSON NULL,
    schema_version VARCHAR(10) NOT NULL DEFAULT '1',
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_diario_operacional UNIQUE (versao_regra, data_pregao),
    CONSTRAINT fk_diario_regra FOREIGN KEY (versao_regra) REFERENCES regra_operacional (versao_regra),
    CONSTRAINT ck_diario_status CHECK (status_sistema IN
        ('NAO_OPERAVEL','EM_OBSERVACAO','PAPER_TRADING_ELEGIVEL','BLOQUEADO'))
);

-- --------------------------------------------------------------------------------------------
-- Trilha de auditoria e fila de saida dos eventos operacional.*.v1 (OPR-INFRA-2): grava antes de
-- publicar; `publicado_em` NULL = ainda nao saiu. Somente insercao.
CREATE TABLE IF NOT EXISTS evento_operacional (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    event_id CHAR(36) NOT NULL,
    correlation_id CHAR(36) NULL,
    tipo VARCHAR(25) NOT NULL,
    versao_regra VARCHAR(30) NOT NULL,
    data_pregao DATE NOT NULL,
    simbolo VARCHAR(12) NULL,
    operacao_id BIGINT NULL,
    payload_json JSON NOT NULL,
    schema_version VARCHAR(10) NOT NULL DEFAULT '1',

    publicado_em TIMESTAMP NULL,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_evento_operacional UNIQUE (event_id),
    CONSTRAINT fk_evento_operacao FOREIGN KEY (operacao_id) REFERENCES operacao_simulada (id),
    CONSTRAINT ck_evento_tipo CHECK (tipo IN ('SINAL_GERADO','POSICAO_ABERTA','POSICAO_FECHADA',
        'DIARIO_AVALIADO','ALERTA_RISCO','BLOQUEIO_DADO','BLOQUEIO_LIQUIDEZ','STATUS_ALTERADO')),
    INDEX idx_evento_pregao (data_pregao, tipo),
    INDEX idx_evento_pendente (publicado_em)
);

-- --------------------------------------------------------------------------------------------
-- Versao inicial da regra com os valores da DEC-OPR-1 (gerar-insights/SPEC.md, "Parametros
-- fixados"). Nasce RASCUNHO: o gerar-insights so a marca ATIVA quando OPR-INS-1..5 estiverem prontas.
INSERT INTO regra_operacional (versao_regra, descricao, parametros_json, regras_ir_versao, vigente_desde, status)
SELECT 'OPR-2026.10.10-1',
       'DEC-OPR-1: liquidez, tamanho de posicao, saida e IR fixados em 2026-10-10 (paper trading).',
       JSON_OBJECT(
           'capital_teorico', 100000,
           'liquidez', JSON_OBJECT('volume_financeiro_medio_63d_min', 5000000, 'negocios_medio_63d_min', 500,
                                   'presenca_63d_min', 0.95, 'spread_mediano_63d_max', 0.005,
                                   'fator_faixa_alta', 2, 'dias_iliquido_saida', 5),
           'tamanho', JSON_OBJECT('risco_por_operacao', 0.005, 'stop_atr', 2, 'exposicao_max_ativo', 0.05,
                                  'exposicao_max_setor', 0.20, 'max_participacao_adtv_21d', 0.01,
                                  'max_posicoes', 15, 'posicao_minima', 500, 'lote_padrao', 100,
                                  'redutor_liquidez_media', 0.5, 'redutor_vol_p80', 0.75),
           'saida', JSON_OBJECT('execucao', 'ABERTURA_D_MAIS_1', 'stop_atr', 2, 'trailing_atr', 3,
                                'trailing_armado_apos_atr', 1,
                                'prioridade', JSON_ARRAY('EVENTO', 'STOP', 'LIQUIDEZ', 'SINAL', 'PRAZO')),
           'custos', JSON_OBJECT('custo_fixo_bps', 10),
           'trava', JSON_OBJECT('min_pregoes', 63, 'benchmark', 'CDI_LIQUIDO_IR')),
       'ir/2026.json', '2026-10-10', 'RASCUNHO'
WHERE NOT EXISTS (SELECT 1 FROM regra_operacional WHERE versao_regra = 'OPR-2026.10.10-1');
