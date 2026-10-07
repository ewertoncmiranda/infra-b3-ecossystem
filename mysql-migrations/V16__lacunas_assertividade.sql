-- V16__lacunas_assertividade.sql
-- L1 e L6: DVA e DMPL no fato_contabil (DMPL tem a coluna do patrimonio).
ALTER TABLE fato_contabil
    ADD COLUMN coluna_df VARCHAR(60) NOT NULL DEFAULT '' AFTER cd_conta,
    DROP INDEX uq_fato_contabil,
    ADD UNIQUE KEY uq_fato_contabil
        (cnpj, tipo_doc, grupo, demonstracao, dt_fim_exerc, dt_ini_exerc, cd_conta, coluna_df);

-- L1: proventos por periodo (DVA). DFP = ano; ITR = trimestre isolado.
CREATE TABLE provento_contabil (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    cnpj                VARCHAR(20)       NOT NULL,
    tipo_doc            VARCHAR(5)        NOT NULL,
    dt_ini_exerc        DATE              NOT NULL,
    dt_fim_exerc        DATE              NOT NULL,
    versao              SMALLINT UNSIGNED NOT NULL,
    data_entrega        DATE              NULL,
    jcp                 DECIMAL(24,2)     NULL,
    dividendos          DECIMAL(24,2)     NULL,
    total               DECIMAL(24,2) GENERATED ALWAYS AS (COALESCE(jcp, 0) + COALESCE(dividendos, 0)) STORED,
    acoes_ex_tesouraria BIGINT            NULL,
    por_acao            DECIMAL(18,8)     NULL,
    origem              VARCHAR(20)       NOT NULL DEFAULT 'CVM_DVA',
    cobertura_json      JSON              NULL,
    criado_em           DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_provento_contabil (cnpj, tipo_doc, dt_fim_exerc),
    KEY idx_provento_contabil_entrega (cnpj, data_entrega),
    CONSTRAINT chk_provento_contabil_tipo_doc CHECK (tipo_doc IN ('DFP', 'ITR'))
);

-- L2: desdobramento, grupamento e bonificacao (inferidos).
CREATE TABLE evento_corporativo (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    simbolo        VARCHAR(12)    NOT NULL,
    cnpj           VARCHAR(20)    NULL,
    data_efeito    DATE           NOT NULL,
    tipo           VARCHAR(20)    NOT NULL,
    fator_acoes    DECIMAL(20,10) NOT NULL,
    fator_preco    DECIMAL(20,10) GENERATED ALWAYS AS (1 / fator_acoes) STORED,
    origem         VARCHAR(30)    NOT NULL,
    confianca      DECIMAL(5,4)   NULL,
    evidencia_json JSON           NULL,
    criado_em      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_evento_corporativo (simbolo, data_efeito, tipo),
    KEY idx_evento_corporativo_cnpj (cnpj, data_efeito),
    CONSTRAINT chk_evento_corporativo_tipo CHECK (tipo IN ('DESDOBRAMENTO', 'GRUPAMENTO', 'BONIFICACAO')),
    CONSTRAINT chk_evento_corporativo_fator CHECK (fator_acoes > 0),
    CONSTRAINT chk_evento_corporativo_origem CHECK (origem IN ('INFERIDO_CVM_COTAHIST', 'MANUAL'))
);

-- L3/L4: sem tabela nova (fato_contabil, indicador_fundamentalista,
-- cvm_composicao_capital e cotacao_b3_diaria so crescem).

-- L6: contas para qualidade (liquidez, margem bruta, Piotroski).
ALTER TABLE indicador_fundamentalista
    ADD COLUMN ativo_total        DECIMAL(24,2) NULL AFTER patrimonio_liquido,
    ADD COLUMN ativo_circulante   DECIMAL(24,2) NULL AFTER ativo_total,
    ADD COLUMN passivo_circulante DECIMAL(24,2) NULL AFTER ativo_circulante,
    ADD COLUMN lucro_bruto        DECIMAL(24,2) NULL AFTER receita_liquida;

-- L7: agrupamento de setores e regra de valuation por grupo.
CREATE TABLE setor_grupo (
    setor_cvm       VARCHAR(60) PRIMARY KEY,
    grupo_setor     VARCHAR(40) NOT NULL,
    regra_valuation VARCHAR(20) NOT NULL DEFAULT 'GRAHAM',
    observacao      VARCHAR(300) NULL,
    CONSTRAINT chk_setor_grupo_regra CHECK (regra_valuation IN ('GRAHAM', 'PL_SETOR', 'PVP_SETOR', 'DIVIDENDOS'))
);
INSERT INTO setor_grupo (setor_cvm, grupo_setor)
SELECT DISTINCT setor, 'A_CLASSIFICAR' FROM cvm_empresa WHERE setor IS NOT NULL;

-- L5, L6, L8: fatores em formato longo.
CREATE TABLE fator_definicao (
    codigo            VARCHAR(40)  PRIMARY KEY,
    familia           VARCHAR(20)  NOT NULL,
    descricao         VARCHAR(300) NOT NULL,
    fonte             VARCHAR(20)  NOT NULL,
    direcao_esperada  TINYINT      NOT NULL,
    defasagem_pregoes SMALLINT     NOT NULL DEFAULT 0,
    versao_calculo    VARCHAR(20)  NOT NULL,
    ativo             BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_fator_definicao_familia CHECK (familia IN ('PRECO', 'QUALIDADE', 'VALOR', 'EVENTO')),
    CONSTRAINT chk_fator_definicao_fonte CHECK (fonte IN ('COTAHIST', 'CVM_DFP_ITR', 'CVM_IPE', 'COTAHIST_CVM')),
    CONSTRAINT chk_fator_definicao_direcao CHECK (direcao_esperada IN (-1, 0, 1))
);

CREATE TABLE fator_valor (
    simbolo            VARCHAR(12)    NOT NULL,
    data_referencia    DATE           NOT NULL,
    fator_codigo       VARCHAR(40)    NOT NULL,
    valor              DECIMAL(24,10) NULL,
    percentil_universo DECIMAL(7,4)   NULL,
    percentil_setor    DECIMAL(7,4)   NULL,
    grupo_setor        VARCHAR(40)    NULL,
    calculado_em       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (simbolo, data_referencia, fator_codigo),
    KEY idx_fator_valor_data (data_referencia, fator_codigo),
    CONSTRAINT fk_fator_valor_definicao FOREIGN KEY (fator_codigo) REFERENCES fator_definicao (codigo)
);

INSERT INTO fator_definicao (codigo, familia, descricao, fonte, direcao_esperada, defasagem_pregoes, versao_calculo) VALUES
    ('MOMENTO_12_1',          'PRECO',     'Retorno de 12 meses excluindo o ultimo mes', 'COTAHIST', 1, 21, '1'),
    ('VOLATILIDADE_12M',      'PRECO',     'Desvio-padrao anualizado dos retornos diarios em 12 meses', 'COTAHIST', -1, 0, '1'),
    ('LIQUIDEZ_63D',          'PRECO',     'Volume financeiro medio diario em 63 pregoes', 'COTAHIST', 1, 0, '1'),
    ('BETA_12M',              'PRECO',     'Beta contra a media do universo em 12 meses', 'COTAHIST', -1, 0, '1'),
    ('DRAWDOWN_12M',          'PRECO',     'Queda do pico em 12 meses', 'COTAHIST', 1, 0, '1'),
    ('ROIC',                  'QUALIDADE', 'EBIT sobre capital investido (PL + divida liquida)', 'CVM_DFP_ITR', 1, 0, '1'),
    ('ALAVANCAGEM',           'QUALIDADE', 'Divida liquida sobre patrimonio liquido', 'CVM_DFP_ITR', -1, 0, '1'),
    ('MARGEM_BRUTA',          'QUALIDADE', 'Lucro bruto sobre receita liquida', 'CVM_DFP_ITR', 1, 0, '1'),
    ('ACCRUALS',              'QUALIDADE', '(Lucro liquido - fluxo de caixa operacional) sobre ativo total', 'CVM_DFP_ITR', -1, 0, '1'),
    ('PIOTROSKI',             'QUALIDADE', 'Escore F de Piotroski (0 a 9)', 'CVM_DFP_ITR', 1, 0, '1'),
    ('CRESCIMENTO_LPA',       'QUALIDADE', 'Variacao do LPA dos ultimos 12 meses contra 12 meses antes', 'CVM_DFP_ITR', 1, 0, '1'),
    ('EARNINGS_YIELD',        'VALOR',     'LPA dos ultimos 12 meses sobre preco', 'COTAHIST_CVM', 1, 0, '1'),
    ('BOOK_TO_MARKET',        'VALOR',     'VPA sobre preco', 'COTAHIST_CVM', 1, 0, '1'),
    ('DIVIDEND_YIELD',        'VALOR',     'Proventos por acao em 12 meses (DVA) sobre preco', 'COTAHIST_CVM', 1, 0, '1'),
    ('FATOS_RELEVANTES_90D',  'EVENTO',    'Fatos relevantes entregues nos ultimos 90 dias', 'CVM_IPE', 0, 0, '1'),
    ('AVISOS_PROVENTOS_180D', 'EVENTO',    'Avisos de proventos entregues nos ultimos 180 dias', 'CVM_IPE', 1, 0, '1');

-- L8: contagem de comunicados por empresa e janela de entrega.
ALTER TABLE comunicado_cvm
    ADD KEY idx_comunicado_evento (cnpj, categoria, data_entrega);

-- L9: fatores de referencia construidos (no lugar do NEFIN).
CREATE TABLE fator_mercado_mensal (
    data_referencia DATE          NOT NULL,
    fator_codigo    VARCHAR(10)   NOT NULL,
    versao_calculo  VARCHAR(20)   NOT NULL,
    retorno         DECIMAL(14,8) NOT NULL,
    n_ativos_long   INT           NULL,
    n_ativos_short  INT           NULL,
    calculado_em    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (data_referencia, fator_codigo, versao_calculo),
    CONSTRAINT chk_fator_mercado_codigo CHECK (fator_codigo IN ('MKT', 'SMB', 'HML', 'WML', 'IML', 'QMJ'))
);

-- Metodo: ranking, janelas sucessivas e registro de tentativas.
ALTER TABLE backtest_execucao
    ADD COLUMN metodo            VARCHAR(20) NOT NULL DEFAULT 'CLASSES' AFTER status,
    ADD COLUMN esquema_validacao VARCHAR(20) NOT NULL DEFAULT 'CORTE_UNICO' AFTER metodo,
    ADD COLUMN hipotese          TEXT        NULL AFTER esquema_validacao,
    ADD COLUMN numero_tentativa  INT         NULL AFTER hipotese,
    ADD CONSTRAINT chk_backtest_execucao_metodo CHECK (metodo IN ('CLASSES', 'RANKING')),
    ADD CONSTRAINT chk_backtest_execucao_esquema CHECK (esquema_validacao IN ('CORTE_UNICO', 'JANELAS_SUCESSIVAS'));

CREATE TABLE backtest_ranking_mes (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    execucao_id     BIGINT       NOT NULL,
    versao_regra    VARCHAR(20)  NOT NULL,
    janela          VARCHAR(20)  NOT NULL,
    data_referencia DATE         NOT NULL,
    horizonte       SMALLINT     NOT NULL,
    ic_spearman     DECIMAL(8,6) NULL,
    n_ativos        INT          NOT NULL,
    UNIQUE KEY uq_backtest_ranking_mes (execucao_id, versao_regra, janela, data_referencia, horizonte),
    CONSTRAINT fk_backtest_ranking_mes_execucao FOREIGN KEY (execucao_id) REFERENCES backtest_execucao (id) ON DELETE CASCADE
);

CREATE TABLE backtest_ranking_quintil (
    ranking_mes_id BIGINT        NOT NULL,
    quintil        TINYINT       NOT NULL,
    retorno_medio  DECIMAL(12,6) NULL,
    n_ativos       INT           NOT NULL,
    PRIMARY KEY (ranking_mes_id, quintil),
    CONSTRAINT fk_backtest_ranking_quintil_mes FOREIGN KEY (ranking_mes_id) REFERENCES backtest_ranking_mes (id) ON DELETE CASCADE,
    CONSTRAINT chk_backtest_ranking_quintil CHECK (quintil BETWEEN 1 AND 5)
);

-- L1, L2 e L5: campos do COTAHIST que o leitor ignora hoje (achados da
-- Sessao 01, conferidos em 30-09-2026). marca_ex = sufixo do ESPECI no dia
-- ex (EJ, ED, EB, EG, ES...); fator_cotacao = FATCOT (AZUL53 1.000.000,
-- GOLL54 1.000: preco gravado hoje multiplicado); preco_medio = PREMED
-- (VWAP); melhores ofertas no fechamento = PREOFC/PREOFV (spread real).
ALTER TABLE cotacao_b3_diaria
    ADD COLUMN especificacao        VARCHAR(10)   NULL AFTER simbolo,
    ADD COLUMN marca_ex             VARCHAR(4)    NULL AFTER especificacao,
    ADD COLUMN fator_cotacao        INT           NOT NULL DEFAULT 1 AFTER marca_ex,
    ADD COLUMN preco_medio          DECIMAL(14,4) NULL AFTER fechamento,
    ADD COLUMN melhor_oferta_compra DECIMAL(14,4) NULL AFTER preco_medio,
    ADD COLUMN melhor_oferta_venda  DECIMAL(14,4) NULL AFTER melhor_oferta_compra,
    ADD KEY idx_cotacao_b3_marca_ex (marca_ex, data_pregao);
