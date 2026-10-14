-- TASK-39: checagens de qualidade dos dados gravadas pelo ETL apos cada carga.
-- Cada linha e um problema detectado em um papel ou no universo inteiro
-- (simbolo NULL = checagem agrega). O ETL reabre as checagens do mesmo tipo
-- a cada carga completa (marcar_resolvidos + inserir); o gestor le as pendentes
-- para exibir em /validacao/saude-dados (CTR-12).
CREATE TABLE IF NOT EXISTS checagem_dados (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    tipo        VARCHAR(50)  NOT NULL,
    simbolo     VARCHAR(12)  NULL,
    descricao   VARCHAR(500) NOT NULL,
    severidade  VARCHAR(10)  NOT NULL DEFAULT 'AVISO',
    detectado_em TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolvido_em TIMESTAMP   NULL,
    INDEX idx_pendentes (resolvido_em, detectado_em),
    INDEX idx_tipo_simbolo (tipo, simbolo)
) ENGINE=InnoDB;
