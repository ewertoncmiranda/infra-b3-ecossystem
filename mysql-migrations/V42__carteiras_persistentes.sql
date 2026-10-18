-- CARTDB-INFRA-1: persistencia da carteira simulada ja apresentada pelo frontend.
-- Este schema e de uma unica instancia confiavel, nao de usuarios autenticados.
-- Nao representa ordens, custodia, quantidade executada ou retorno realizado.

CREATE TABLE carteira (
    id           VARCHAR(64)  NOT NULL COMMENT 'ID textual compatível com b3-carteiras do frontend',
    nome         VARCHAR(120) NOT NULL,
    estrategia   VARCHAR(80)  NOT NULL,
    cor          VARCHAR(7)  NOT NULL COMMENT 'Cor CSS hexadecimal, formato #RGB ou #RRGGBB',
    moeda_base   CHAR(3)      NOT NULL DEFAULT 'BRL',
    status       VARCHAR(12)  NOT NULL DEFAULT 'ATIVA',
    criada_em    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizada_em DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_carteira_status_nome (status, nome),
    CONSTRAINT ck_carteira_cor CHECK (cor REGEXP '^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$'),
    CONSTRAINT ck_carteira_status CHECK (status IN ('ATIVA', 'ARQUIVADA'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE carteira_ativo (
    carteira_id    VARCHAR(64)  NOT NULL,
    simbolo        VARCHAR(12)  NOT NULL,
    data_entrada   DATE         NOT NULL,
    capital_alocado DECIMAL(18,2) NOT NULL COMMENT 'Alocação simulada, não valor de ordem executada',
    criado_em      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (carteira_id, simbolo),
    KEY idx_carteira_ativo_simbolo (simbolo),
    CONSTRAINT fk_carteira_ativo_carteira
        FOREIGN KEY (carteira_id) REFERENCES carteira (id)
        ON DELETE CASCADE,
    CONSTRAINT ck_carteira_ativo_capital CHECK (capital_alocado > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
