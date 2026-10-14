-- V20__opcao_b3_diaria.sql
-- TASK-E16 / DEC-E09: tabela dedicada para cotacoes diarias de opcoes da B3
-- (COTAHIST BDI 12=calls, BDI 14=puts).
-- Campos exclusivos de opcoes (data_vencimento, preco_exercicio) ficam aqui,
-- sem poluir cotacao_b3_diaria com NULLs em massa.

CREATE TABLE opcao_b3_diaria (
    id                BIGINT        NOT NULL AUTO_INCREMENT,
    simbolo           VARCHAR(12)   NOT NULL,
    bdi               VARCHAR(2)    NOT NULL COMMENT '12=call, 14=put',
    data_pregao       DATE          NOT NULL,
    data_vencimento   DATE          NOT NULL,
    preco_exercicio   DECIMAL(14,4) NOT NULL,
    abertura          DECIMAL(14,4) NULL,
    maxima            DECIMAL(14,4) NULL,
    minima            DECIMAL(14,4) NULL,
    fechamento        DECIMAL(14,4) NULL,
    preco_medio       DECIMAL(14,4) NULL,
    volume            BIGINT        NULL,
    numero_negocios   INT           NULL,
    volume_financeiro DECIMAL(22,2) NULL,
    fator_cotacao     INT           NOT NULL DEFAULT 1,
    isin              VARCHAR(12)   NULL,
    criado_em         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_opcao_b3_diaria (simbolo, data_pregao),
    KEY idx_opcao_b3_vencimento (data_vencimento),
    KEY idx_opcao_b3_isin (isin)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
