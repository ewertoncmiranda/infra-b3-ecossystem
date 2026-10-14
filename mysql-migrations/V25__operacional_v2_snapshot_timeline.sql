-- OPRV2-INFRA-2: projecoes operacionais para leitura pelo gestor e painel.
-- Os payloads completos deverao seguir os contratos JSON Schema V2 ainda em definicao.
-- Esta migration nao duplica as tabelas de operacao/diario/eventos do OPR v1 (V23).

CREATE TABLE IF NOT EXISTS ticker_operacional_snapshot (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(12) NOT NULL,
    data_pregao DATE NOT NULL,
    versao_regra VARCHAR(30) NOT NULL,
    status_sistema VARCHAR(25) NOT NULL,
    faixa_liquidez VARCHAR(15) NULL,
    payload_json JSON NOT NULL,
    schema_version VARCHAR(10) NOT NULL DEFAULT '2',

    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_ticker_operacional_snapshot UNIQUE (simbolo, data_pregao, versao_regra),
    CONSTRAINT ck_ticker_snapshot_status CHECK (status_sistema IN
        ('NAO_OPERAVEL','EM_OBSERVACAO','PAPER_TRADING_ELEGIVEL','BLOQUEADO')),
    CONSTRAINT ck_ticker_snapshot_liquidez CHECK (faixa_liquidez IS NULL
        OR faixa_liquidez IN ('ALTA','MEDIA','INSUFICIENTE')),
    INDEX idx_ticker_snapshot_pregao_status (data_pregao, status_sistema),
    INDEX idx_ticker_snapshot_simbolo_pregao (simbolo, data_pregao)
);

CREATE TABLE IF NOT EXISTS ticker_operacional_timeline (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    event_id CHAR(36) NOT NULL,
    simbolo VARCHAR(12) NOT NULL,
    data_pregao DATE NOT NULL,
    ocorrido_em TIMESTAMP NOT NULL,
    tipo_evento VARCHAR(30) NOT NULL,
    categoria VARCHAR(15) NOT NULL,
    severidade VARCHAR(12) NOT NULL,
    codigo VARCHAR(80) NOT NULL,
    payload_json JSON NOT NULL,
    schema_version VARCHAR(10) NOT NULL DEFAULT '2',

    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_ticker_operacional_timeline_event UNIQUE (event_id),
    CONSTRAINT ck_ticker_timeline_tipo CHECK (tipo_evento IN
        ('SINAL_ALTERADO','POSICAO_ABERTA','POSICAO_FECHADA','BLOQUEIO','EVENTO_CVM',
         'PROVENTO','SALTO_PRECO','CONFIANCA_ALTERADA','ALERTA')),
    CONSTRAINT ck_ticker_timeline_categoria CHECK (categoria IN
        ('DADO','LIQUIDEZ','RISCO','EVENTO','SINAL','SISTEMA')),
    CONSTRAINT ck_ticker_timeline_severidade CHECK (severidade IN ('INFO','ATENCAO','CRITICO')),
    INDEX idx_ticker_timeline_simbolo_tempo (simbolo, ocorrido_em),
    INDEX idx_ticker_timeline_categoria_severidade (categoria, severidade, ocorrido_em),
    INDEX idx_ticker_timeline_pregao (simbolo, data_pregao)
);
