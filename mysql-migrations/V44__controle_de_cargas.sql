-- CARGA-INFRA-1: controle das cargas do ETL (Plano CARGA, SPEC do hub).
-- Uma linha em carga_execucao por disparo (rotina da manha, painel ou API) e
-- uma em carga_etapa por etapa dele, com o que foi carregado, alertas e erros.
-- etl_execucao (por arquivo baixado) passa a apontar para a carga que o
-- processou. Migration aditiva: nao altera nem apaga dados existentes.

CREATE TABLE carga_execucao (
    id              CHAR(36)     NOT NULL COMMENT 'UUID gerado pelo ETL',
    tipo            VARCHAR(12)  NOT NULL,
    solicitada_por  VARCHAR(20)  NOT NULL,
    parametros_json JSON         NULL COMMENT '{ anos, simbolos, etapas, forcar }',
    status          VARCHAR(20)  NOT NULL DEFAULT 'PENDENTE',
    versao_etl      VARCHAR(40)  NULL COMMENT 'Tag da imagem ou commit do ETL',
    criada_em       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'UTC',
    iniciada_em     DATETIME     NULL,
    finalizada_em   DATETIME     NULL,
    duracao_ms      BIGINT       NULL,
    etapas_ok       INT          NOT NULL DEFAULT 0,
    etapas_alerta   INT          NOT NULL DEFAULT 0,
    etapas_falha    INT          NOT NULL DEFAULT 0,
    mensagem_erro   TEXT         NULL COMMENT 'Falha fora das etapas: lock, banco, configuracao',
    atualizada_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_carga_execucao_criada (criada_em),
    KEY idx_carga_execucao_status (status, criada_em),
    CONSTRAINT ck_carga_execucao_tipo CHECK (tipo IN ('ROTINA', 'COMPLETA', 'PARCIAL')),
    CONSTRAINT ck_carga_execucao_solicitante CHECK (solicitada_por IN ('ROTINA_MANHA', 'PAINEL', 'API')),
    CONSTRAINT ck_carga_execucao_status CHECK (status IN (
        'PENDENTE', 'EXECUTANDO', 'SUCESSO', 'SUCESSO_COM_ALERTA', 'SUCESSO_PARCIAL', 'FALHA', 'INTERROMPIDA'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE carga_etapa (
    id            BIGINT       NOT NULL AUTO_INCREMENT,
    execucao_id   CHAR(36)     NOT NULL,
    ordem         SMALLINT     NOT NULL,
    etapa         VARCHAR(30)  NOT NULL,
    status        VARCHAR(15)  NOT NULL DEFAULT 'PENDENTE',
    iniciada_em   DATETIME     NULL,
    finalizada_em DATETIME     NULL,
    duracao_ms    BIGINT       NULL,
    metricas_json JSON         NULL COMMENT 'O que foi carregado: anos, lidos, gravados, rejeitados por motivo...',
    alertas_json  JSON         NULL,
    erros_json    JSON         NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_carga_etapa_execucao (execucao_id, etapa),
    KEY idx_carga_etapa_etapa_status (etapa, status, finalizada_em),
    CONSTRAINT fk_carga_etapa_execucao
        FOREIGN KEY (execucao_id) REFERENCES carga_execucao (id)
        ON DELETE CASCADE,
    CONSTRAINT ck_carga_etapa_etapa CHECK (etapa IN (
        'COTAHIST', 'LIQUIDEZ', 'PRONTIDAO', 'QUALIDADE_OPCOES', 'CONCILIACAO',
        'DFP', 'TTM', 'IPE', 'DVA', 'EVENTOS', 'CHECAGENS')),
    CONSTRAINT ck_carga_etapa_status CHECK (status IN (
        'PENDENTE', 'EXECUTANDO', 'SUCESSO', 'SEM_MUDANCA', 'ALERTA', 'FALHA', 'PULADA'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Cada arquivo baixado (etl_execucao) aponta para a carga que o processou.
-- Linhas antigas ficam NULL; apagar uma carga nao apaga o historico de arquivos.
ALTER TABLE etl_execucao
    ADD COLUMN carga_execucao_id CHAR(36) NULL COMMENT 'Carga (carga_execucao) que processou o arquivo',
    ADD KEY idx_etl_execucao_carga (carga_execucao_id),
    ADD CONSTRAINT fk_etl_execucao_carga
        FOREIGN KEY (carga_execucao_id) REFERENCES carga_execucao (id)
        ON DELETE SET NULL;

-- Por etapa: a ultima tentativa (qualquer status, exceto PULADA) e o ultimo
-- sucesso (SUCESSO ou SEM_MUDANCA). ALERTA conta como tentativa, nao como
-- sucesso: a etapa rodou mas gravou nada onde era esperado gravar.
CREATE OR REPLACE VIEW vw_carga_ultima AS
WITH tentativas AS (
    SELECT e.etapa,
           e.status,
           e.execucao_id,
           COALESCE(e.finalizada_em, e.iniciada_em, x.criada_em) AS quando,
           ROW_NUMBER() OVER (
               PARTITION BY e.etapa
               ORDER BY COALESCE(e.iniciada_em, x.criada_em) DESC, e.id DESC) AS posicao
    FROM carga_etapa e
    JOIN carga_execucao x ON x.id = e.execucao_id
    WHERE e.status <> 'PULADA'
),
sucessos AS (
    SELECT e.etapa,
           e.execucao_id,
           e.finalizada_em AS quando,
           ROW_NUMBER() OVER (
               PARTITION BY e.etapa
               ORDER BY e.finalizada_em DESC, e.id DESC) AS posicao
    FROM carga_etapa e
    WHERE e.status IN ('SUCESSO', 'SEM_MUDANCA')
      AND e.finalizada_em IS NOT NULL
)
SELECT t.etapa,
       t.quando      AS ultima_tentativa_em,
       t.status      AS ultimo_status,
       t.execucao_id AS ultima_execucao_id,
       s.quando      AS ultimo_sucesso_em,
       s.execucao_id AS ultimo_sucesso_execucao_id
FROM tentativas t
LEFT JOIN sucessos s ON s.etapa = t.etapa AND s.posicao = 1
WHERE t.posicao = 1;
