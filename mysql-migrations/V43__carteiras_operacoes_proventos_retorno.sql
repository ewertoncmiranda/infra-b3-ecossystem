-- CARTDB-INFRA-2: evolui Carteiras para operacoes informadas, recebimentos e
-- snapshots persistidos. Escopo da aplicacao: instancia compartilhada,
-- single-user; carteira.nome e apenas descritivo. Nao representa custodia.
-- V42 permanece imutavel. Nenhum registro de carteira/carteira_ativo e
-- transformado em compra, quantidade, preco, recebimento ou retorno.

CREATE TABLE carteira_operacao (
    id                 CHAR(36)      NOT NULL,
    carteira_id        VARCHAR(64)   NOT NULL,
    tipo               VARCHAR(12)   NOT NULL COMMENT 'COMPRA, VENDA, APORTE, RETIRADA, TAXA, IMPOSTO ou ESTORNO',
    operacao_referenciada_id CHAR(36) NULL COMMENT 'Operacao original revertida; preenchido somente em ESTORNO',
    simbolo            VARCHAR(12)   NULL COMMENT 'Obrigatorio para COMPRA/VENDA; ausente para fluxo de caixa geral',
    executada_em       DATETIME      NOT NULL,
    quantidade         DECIMAL(24,8) NULL COMMENT 'Quantidade informada pelo usuario para COMPRA/VENDA',
    preco_unitario     DECIMAL(20,8) NULL COMMENT 'Preco efetivamente informado para COMPRA/VENDA',
    valor_bruto        DECIMAL(20,2) NOT NULL COMMENT 'Valor positivo antes de custos/impostos',
    custos             DECIMAL(20,2) NOT NULL DEFAULT 0.00,
    impostos           DECIMAL(20,2) NOT NULL DEFAULT 0.00,
    valor_liquido      DECIMAL(20,2) NOT NULL COMMENT 'Impacto assinado no caixa: negativo para debito, positivo para credito',
    moeda              CHAR(3)       NOT NULL DEFAULT 'BRL',
    origem             VARCHAR(16)   NOT NULL DEFAULT 'MANUAL' COMMENT 'MANUAL ou IMPORTACAO',
    chave_idempotencia VARCHAR(100)  NOT NULL,
    criado_em          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_carteira_operacao_carteira_id (carteira_id, id),
    UNIQUE KEY uq_carteira_operacao_idempotencia (carteira_id, chave_idempotencia),
    UNIQUE KEY uq_carteira_operacao_estorno (carteira_id, operacao_referenciada_id),
    KEY idx_carteira_operacao_data (carteira_id, executada_em),
    KEY idx_carteira_operacao_ativo (carteira_id, simbolo, executada_em),
    CONSTRAINT fk_carteira_operacao_carteira FOREIGN KEY (carteira_id)
        REFERENCES carteira (id),
    CONSTRAINT fk_carteira_operacao_referenciada FOREIGN KEY (carteira_id, operacao_referenciada_id)
        REFERENCES carteira_operacao (carteira_id, id),
    CONSTRAINT ck_carteira_operacao_tipo CHECK (tipo IN ('COMPRA','VENDA','APORTE','RETIRADA','TAXA','IMPOSTO','ESTORNO')),
    CONSTRAINT ck_carteira_operacao_origem CHECK (origem IN ('MANUAL','IMPORTACAO')),
    CONSTRAINT ck_carteira_operacao_valores CHECK (valor_bruto >= 0 AND custos >= 0 AND impostos >= 0),
    CONSTRAINT ck_carteira_operacao_trade CHECK (
        (tipo IN ('COMPRA','VENDA') AND simbolo IS NOT NULL AND quantidade > 0 AND preco_unitario > 0)
        OR
        (tipo = 'ESTORNO' AND (
            (simbolo IS NULL AND quantidade IS NULL AND preco_unitario IS NULL)
            OR (simbolo IS NOT NULL AND quantidade > 0 AND preco_unitario > 0)
        ))
        OR
        (tipo NOT IN ('COMPRA','VENDA','ESTORNO') AND simbolo IS NULL AND quantidade IS NULL AND preco_unitario IS NULL)
    ),
    CONSTRAINT ck_carteira_operacao_referencia CHECK (
        (tipo = 'ESTORNO' AND operacao_referenciada_id IS NOT NULL)
        OR (tipo <> 'ESTORNO' AND operacao_referenciada_id IS NULL)
    ),
    CONSTRAINT ck_carteira_operacao_fluxo CHECK (
        (tipo = 'COMPRA' AND valor_liquido = -(valor_bruto + custos + impostos))
        OR (tipo = 'VENDA' AND valor_liquido = valor_bruto - custos - impostos AND valor_liquido >= 0)
        OR (tipo = 'APORTE' AND valor_liquido > 0)
        OR (tipo IN ('RETIRADA','TAXA','IMPOSTO') AND valor_liquido < 0)
        OR (tipo = 'ESTORNO' AND valor_liquido <> 0)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE carteira_provento_recebido (
    id                    CHAR(36)      NOT NULL,
    carteira_id           VARCHAR(64)   NOT NULL,
    simbolo               VARCHAR(12)   NOT NULL,
    tipo                  VARCHAR(16)   NOT NULL COMMENT 'DIVIDENDO, JCP, RENDIMENTO, AMORTIZACAO ou OUTRO',
    data_ex               DATE          NULL,
    data_pagamento        DATE          NOT NULL,
    quantidade_elegivel   DECIMAL(24,8) NULL,
    valor_por_ativo       DECIMAL(20,8) NULL,
    valor_bruto           DECIMAL(20,2) NOT NULL,
    imposto_retido        DECIMAL(20,2) NOT NULL DEFAULT 0.00,
    valor_liquido         DECIMAL(20,2) NOT NULL,
    moeda                 CHAR(3)       NOT NULL DEFAULT 'BRL',
    referencia_evento     VARCHAR(160)  NULL COMMENT 'Identificador/referencia da fonte, quando disponivel; nao e comprovante',
    chave_idempotencia    VARCHAR(100)  NOT NULL,
    criado_em             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_carteira_provento_idempotencia (carteira_id, chave_idempotencia),
    KEY idx_carteira_provento_data (carteira_id, data_pagamento),
    KEY idx_carteira_provento_ativo (carteira_id, simbolo, data_pagamento),
    CONSTRAINT fk_carteira_provento_carteira FOREIGN KEY (carteira_id)
        REFERENCES carteira (id),
    CONSTRAINT ck_carteira_provento_tipo CHECK (tipo IN ('DIVIDENDO','JCP','RENDIMENTO','AMORTIZACAO','OUTRO')),
    CONSTRAINT ck_carteira_provento_valores CHECK (
        valor_bruto >= 0 AND imposto_retido >= 0 AND valor_liquido >= 0
        AND valor_liquido = valor_bruto - imposto_retido
        AND imposto_retido <= valor_bruto
        AND (quantidade_elegivel IS NULL OR quantidade_elegivel > 0)
        AND (valor_por_ativo IS NULL OR valor_por_ativo >= 0)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE carteira_ativo_valuation_diaria (
    carteira_id             VARCHAR(64)   NOT NULL,
    simbolo                 VARCHAR(12)   NOT NULL,
    data_referencia         DATE          NOT NULL,
    quantidade              DECIMAL(24,8) NOT NULL,
    preco_fechamento        DECIMAL(20,8) NOT NULL,
    data_pregao_preco       DATE          NOT NULL,
    fonte_preco             VARCHAR(40)   NOT NULL DEFAULT 'COTAHIST_B3',
    valor_mercado           DECIMAL(22,2) NOT NULL,
    versao_calculo          VARCHAR(40)   NOT NULL,
    calculado_em            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (carteira_id, simbolo, data_referencia, versao_calculo),
    KEY idx_carteira_valuation_data (data_referencia, carteira_id),
    CONSTRAINT fk_carteira_valuation_carteira FOREIGN KEY (carteira_id)
        REFERENCES carteira (id),
    CONSTRAINT ck_carteira_valuation_valores CHECK (quantidade >= 0 AND preco_fechamento >= 0 AND valor_mercado >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE carteira_rentabilidade_diaria (
    carteira_id                VARCHAR(64)   NOT NULL,
    data_referencia            DATE          NOT NULL,
    moeda                      CHAR(3)       NOT NULL DEFAULT 'BRL',
    valor_mercado              DECIMAL(22,2) NOT NULL,
    saldo_caixa                DECIMAL(22,2) NOT NULL DEFAULT 0.00,
    fluxo_externo              DECIMAL(22,2) NOT NULL DEFAULT 0.00 COMMENT 'Aportes/retiradas externos usados pelo metodo',
    proventos_liquidos         DECIMAL(22,2) NOT NULL DEFAULT 0.00,
    resultado_realizado        DECIMAL(22,2) NOT NULL DEFAULT 0.00,
    resultado_nao_realizado    DECIMAL(22,2) NOT NULL DEFAULT 0.00,
    retorno_periodo            DECIMAL(18,10) NULL COMMENT 'Fracao decimal; NULL quando nao calculavel',
    retorno_acumulado          DECIMAL(18,10) NULL,
    metodo                     VARCHAR(16)   NOT NULL COMMENT 'TWR ou INDISPONIVEL ate metodologia aprovada',
    versao_calculo             VARCHAR(40)   NOT NULL,
    calculado_em               DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (carteira_id, data_referencia, versao_calculo),
    KEY idx_carteira_rentabilidade_data (data_referencia, carteira_id),
    CONSTRAINT fk_carteira_rentabilidade_carteira FOREIGN KEY (carteira_id)
        REFERENCES carteira (id),
    CONSTRAINT ck_carteira_rentabilidade_metodo CHECK (metodo IN ('TWR','INDISPONIVEL')),
    CONSTRAINT ck_carteira_rentabilidade_valores CHECK (
        valor_mercado >= 0 AND (retorno_periodo IS NULL OR retorno_periodo > -1)
        AND (retorno_acumulado IS NULL OR retorno_acumulado > -1)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
