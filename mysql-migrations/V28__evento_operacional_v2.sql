-- OPRV2-INS-6: fila de saida dos eventos operacional.*.v2 (snapshot-ticker, consenso-sinais,
-- tese-explicada, timeline-ativo, alerta-ux). Tabela propria porque o CHECK de
-- evento_operacional.tipo (V23) so aceita os tipos v1, e o volume v2 (um snapshot por ativo e
-- pregao) nao deve dividir fila com os alertas do v1.
-- Escritor: gerar-insights (OperabilidadeV2, dentro do diario operacional). Grava antes de publicar;
-- `publicado_em` NULL = ainda nao saiu para sqs-eventos-operacionais-v2. Somente insercao.
-- `event_id` deterministico (tipo + ativo + pregao + conteudo): reprocessar o pregao nao duplica.

CREATE TABLE IF NOT EXISTS evento_operacional_v2 (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    event_id CHAR(36) NOT NULL,
    contrato VARCHAR(30) NOT NULL,
    versao_regra VARCHAR(30) NOT NULL,
    data_pregao DATE NOT NULL,
    simbolo VARCHAR(12) NULL,
    conteudo_hash CHAR(64) NOT NULL,
    payload_json JSON NOT NULL,

    publicado_em TIMESTAMP NULL,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_evento_operacional_v2 UNIQUE (event_id),
    CONSTRAINT ck_evento_v2_contrato CHECK (contrato IN
        ('snapshot-ticker','consenso-sinais','tese-explicada','timeline-ativo','alerta-ux')),
    INDEX idx_evento_v2_pendente (publicado_em),
    INDEX idx_evento_v2_ultimo (simbolo, contrato, data_pregao)
);
