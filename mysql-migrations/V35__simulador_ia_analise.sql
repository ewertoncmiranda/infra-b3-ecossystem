-- SIM-INFRA-3: cache diário de análise de IA por ativo simulado.
-- Uma linha por ativo por dia: segunda chamada do mesmo dia reutiliza a linha existente (upsert).
-- dados_entrada_json preserva o contexto usado, permitindo auditar o que a IA recebeu.

CREATE TABLE simulador_ia_analise (
    id                  BIGINT        NOT NULL AUTO_INCREMENT,
    ativo_id            INT           NOT NULL,
    data_analise        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dados_entrada_json  JSON          NULL,
    analise_texto       TEXT          NULL,
    modelo_ia           VARCHAR(100)  NOT NULL,
    tokens_usados       INT           NULL,
    criado_em           TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_simulador_ia_analise PRIMARY KEY (id),
    CONSTRAINT fk_simulador_ia_analise_ativo FOREIGN KEY (ativo_id) REFERENCES simulador_ativo (id) ON DELETE CASCADE,
    CONSTRAINT uq_simulador_ia_analise_ativo_dia UNIQUE (ativo_id, (DATE(data_analise))),
    INDEX idx_simulador_ia_analise_ativo_data (ativo_id, data_analise)
);
