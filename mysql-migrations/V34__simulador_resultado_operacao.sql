-- SIM-INFRA-2: resultados do simulador e operações associadas.
-- Esta migração cria a base de dados do simulador de operações em três camadas:
-- 1) simulador_resultado: série diária por ativo, pregão e estratégia;
-- 2) simulador_operacao: operações abertas/fechadas do simulador;
-- 3) simulador_operacao_diario: evolução diária de cada operação.
-- O objetivo é permitir análise por ativo, data e estratégia sem duplicar registros.

CREATE TABLE simulador_resultado (
    id                  BIGINT        NOT NULL AUTO_INCREMENT,
    ativo_id            INT           NOT NULL,
    data_pregao         DATE          NOT NULL,
    versao_estrategia   VARCHAR(30)   NOT NULL,
    quintil             TINYINT       NOT NULL DEFAULT 1,
    retorno_pct         DECIMAL(12,8) NULL,
    score               DECIMAL(12,8) NULL,
    parametros_json     JSON          NULL,
    criado_em           TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_simulador_resultado PRIMARY KEY (id),
    CONSTRAINT fk_simulador_resultado_ativo FOREIGN KEY (ativo_id) REFERENCES simulador_ativo (id) ON DELETE CASCADE,
    CONSTRAINT ck_simulador_resultado_quintil CHECK (quintil BETWEEN 1 AND 5),
    CONSTRAINT uq_simulador_resultado_ativo_data_versao UNIQUE (ativo_id, data_pregao, versao_estrategia),
    INDEX idx_simulador_resultado_ativo_data (ativo_id, data_pregao),
    INDEX idx_simulador_resultado_versao (versao_estrategia, data_pregao)
);

CREATE TABLE simulador_operacao (
    id                  BIGINT        NOT NULL AUTO_INCREMENT,
    ativo_id            INT           NOT NULL,
    data_entrada        DATE          NOT NULL,
    capital             DECIMAL(18,2) NOT NULL,
    versao_estrategia   VARCHAR(30)   NOT NULL,
    status              ENUM('PENDENTE', 'ABERTA', 'FECHADA') NOT NULL DEFAULT 'PENDENTE',
    criado_em           TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_simulador_operacao PRIMARY KEY (id),
    CONSTRAINT fk_simulador_operacao_ativo FOREIGN KEY (ativo_id) REFERENCES simulador_ativo (id) ON DELETE CASCADE,
    CONSTRAINT ck_simulador_operacao_capital CHECK (capital > 0),
    INDEX idx_simulador_operacao_ativo_data (ativo_id, data_entrada),
    INDEX idx_simulador_operacao_versao_status (versao_estrategia, status)
);

CREATE TABLE simulador_operacao_diario (
    id                  BIGINT        NOT NULL AUTO_INCREMENT,
    operacao_id         BIGINT        NOT NULL,
    data_pregao         DATE          NOT NULL,
    preco               DECIMAL(18,6) NULL,
    retorno_dia_pct     DECIMAL(12,8) NULL,
    retorno_acum_pct    DECIMAL(12,8) NULL,
    pnl_rs              DECIMAL(18,2) NULL,
    criado_em           TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_simulador_operacao_diario PRIMARY KEY (id),
    CONSTRAINT fk_simulador_operacao_diario_operacao FOREIGN KEY (operacao_id) REFERENCES simulador_operacao (id) ON DELETE CASCADE,
    INDEX idx_simulador_operacao_diario_operacao_pregao (operacao_id, data_pregao),
    INDEX idx_simulador_operacao_diario_data (data_pregao)
);

