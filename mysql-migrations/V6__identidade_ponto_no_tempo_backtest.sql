-- Confiabilidade dos dados e backtest (CTR-12, CTR-13, CTR-14).
--
-- 1. ativo_identidade: um codigo canonico por empresa. A BRAPI ja devolve os
--    tickers novos (AXIA3, EMBJ3, JBSS32, MBRF3) enquanto fundamentos,
--    cotacao e universo ainda usavam os antigos - preco e balanco dessas
--    empresas nunca se encontravam. O FCA nao resolve sozinho: traz o codigo
--    "4030" para a CSN e "ADR" para a Marfrig.
-- 2. indicador_fundamentalista.data_entrega: DT_RECEB da CVM, a data em que o
--    balanco ficou publico. Sem ela o backtest usa lucro que ninguem conhecia.
-- 3. TTM passa a caber nas constraints (a carga TTM nunca gravava).
-- 4. cotacao_b3_diaria: COTAHIST oficial, separado de serie_historica para nao
--    sobrescrever a BRAPI (a checagem cruzada precisa das duas).
-- 5. backtest_execucao / backtest_placar: resultado do walk-forward.
-- 6. Canoniza o que ja existe (universo, cache de cotacao, indicadores).
--
-- Idempotente: o mysql-init de volume novo ja cria tudo isto, e o Flyway
-- reaplica por cima (baselineVersion=1).

CREATE TABLE IF NOT EXISTS ativo_identidade (
    simbolo             VARCHAR(10)  NOT NULL,
    simbolo_canonico    VARCHAR(10)  NOT NULL,
    cnpj                VARCHAR(20)  NULL,
    -- 0 quando o codigo antigo NAO e o mesmo papel (incorporacao, troca por
    -- BDR): a serie de preco dele nao pode ser emendada na do canonico.
    continuidade_preco  TINYINT(1)   NOT NULL DEFAULT 1,
    negociado_ate       DATE         NULL,
    origem              VARCHAR(20)  NOT NULL DEFAULT 'CURADORIA',
    observacao          VARCHAR(255) NULL,
    criado_em           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (simbolo),
    KEY idx_ativo_identidade_canonico (simbolo_canonico)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO ativo_identidade (simbolo, simbolo_canonico, cnpj, continuidade_preco, negociado_ate, observacao) VALUES
    ('AXIA3',  'AXIA3',  '00.001.180/0001-26', 1, NULL, 'Eletrobras, renomeada Axia Energia'),
    ('ELET3',  'AXIA3',  '00.001.180/0001-26', 1, NULL, 'Codigo antigo da Eletrobras (mesmo papel)'),
    ('EMBJ3',  'EMBJ3',  '07.689.002/0001-89', 1, NULL, 'Embraer'),
    ('EMBR3',  'EMBJ3',  '07.689.002/0001-89', 1, NULL, 'Codigo antigo da Embraer (mesmo papel)'),
    ('JBSS32', 'JBSS32', '49.115.815/0001-05', 1, NULL, 'BDR da JBS N.V.'),
    ('JBSS3',  'JBSS32', '02.916.265/0001-60', 0, NULL, 'JBS S.A., trocada por BDR da JBS N.V.: outro emissor'),
    ('MBRF3',  'MBRF3',  '03.853.896/0001-40', 1, NULL, 'Marfrig, renomeada MBRF Global Foods'),
    ('MRFG3',  'MBRF3',  '03.853.896/0001-40', 1, NULL, 'Codigo antigo da Marfrig (mesmo papel)'),
    ('BRFS3',  'MBRF3',  '01.838.723/0001-27', 0, '2025-09-22', 'BRF incorporada pela MBRF: relacao de troca, nao mesmo papel'),
    ('CSNA3',  'CSNA3',  '33.042.730/0001-04', 1, NULL, 'FCA traz o codigo "4030" em vez do ticker'),
    ('RAIZ4',  'RAIZ4',  '33.453.598/0001-23', 1, NULL, 'FCA traz data de fim de negociacao incorreta')
ON DUPLICATE KEY UPDATE
    simbolo_canonico = VALUES(simbolo_canonico),
    cnpj = VALUES(cnpj),
    continuidade_preco = VALUES(continuidade_preco),
    negociado_ate = VALUES(negociado_ate),
    observacao = VALUES(observacao);

-- 2. data de entrega (point-in-time) -----------------------------------------
SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'indicador_fundamentalista'
             AND COLUMN_NAME = 'data_entrega'),
    'SELECT 1',
    'ALTER TABLE indicador_fundamentalista ADD COLUMN data_entrega DATE NULL AFTER tipo_periodo, ADD KEY idx_indicador_simbolo_entrega (simbolo, data_entrega)'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 3. TTM nas constraints -----------------------------------------------------
SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fato_contabil'
             AND CONSTRAINT_NAME = 'chk_fato_contabil_tipo_doc'),
    'ALTER TABLE fato_contabil DROP CHECK chk_fato_contabil_tipo_doc',
    'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
ALTER TABLE fato_contabil ADD CONSTRAINT chk_fato_contabil_tipo_doc CHECK (tipo_doc IN ('DFP', 'ITR', 'TTM'));

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'indicador_fundamentalista'
             AND CONSTRAINT_NAME = 'chk_indicador_tipo_doc'),
    'ALTER TABLE indicador_fundamentalista DROP CHECK chk_indicador_tipo_doc',
    'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
ALTER TABLE indicador_fundamentalista ADD CONSTRAINT chk_indicador_tipo_doc CHECK (tipo_doc IN ('DFP', 'ITR', 'TTM'));

-- 4. COTAHIST oficial ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS cotacao_b3_diaria (
    id                BIGINT        NOT NULL AUTO_INCREMENT,
    -- codigo como negociado NAQUELE dia (ELET3 em 2020, AXIA3 hoje);
    -- quem le junta pela ativo_identidade.
    simbolo           VARCHAR(12)   NOT NULL,
    data_pregao       DATE          NOT NULL,
    abertura          DECIMAL(14,4) NULL,
    maxima            DECIMAL(14,4) NULL,
    minima            DECIMAL(14,4) NULL,
    fechamento        DECIMAL(14,4) NULL,
    volume            BIGINT        NULL,
    numero_negocios   INT           NULL,
    volume_financeiro DECIMAL(22,2) NULL,
    criado_em         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cotacao_b3_diaria (simbolo, data_pregao),
    KEY idx_cotacao_b3_diaria_data (data_pregao)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 5. backtest ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS backtest_execucao (
    id               BIGINT      NOT NULL AUTO_INCREMENT,
    iniciado_em      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finalizado_em    DATETIME    NULL,
    status           VARCHAR(20) NOT NULL,
    inicio_periodo   DATE        NULL,
    fim_periodo      DATE        NULL,
    -- sinais ate esta data calibram; depois dela sao o teste congelado
    corte_calibracao DATE        NOT NULL,
    ativos           INT         NOT NULL DEFAULT 0,
    sinais           INT         NOT NULL DEFAULT 0,
    parametros_json  JSON        NULL,
    observacoes      TEXT        NULL,
    PRIMARY KEY (id),
    CONSTRAINT chk_backtest_execucao_status CHECK (status IN ('EM_ANDAMENTO', 'SUCESSO', 'ERRO'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS backtest_placar (
    id                     BIGINT        NOT NULL AUTO_INCREMENT,
    execucao_id            BIGINT        NOT NULL,
    versao_regra           VARCHAR(20)   NOT NULL,
    periodo                VARCHAR(12)   NOT NULL,
    recomendacao           VARCHAR(20)   NOT NULL,
    horizonte              SMALLINT      NOT NULL,
    avaliados              INT           NOT NULL,
    acertos                INT           NULL,
    taxa_base              DECIMAL(8,6)  NULL,
    retorno_medio          DECIMAL(12,6) NULL,
    excesso_medio_cdi      DECIMAL(12,6) NULL,
    excesso_medio_carteira DECIMAL(12,6) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_backtest_placar (execucao_id, versao_regra, periodo, recomendacao, horizonte),
    CONSTRAINT fk_backtest_placar_execucao FOREIGN KEY (execucao_id)
        REFERENCES backtest_execucao (id) ON DELETE CASCADE,
    CONSTRAINT chk_backtest_placar_periodo CHECK (periodo IN ('CALIBRACAO', 'TESTE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 6. canonizacao do que ja existe ------------------------------------------
-- Universo: alias vira o canonico quando o canonico ainda nao esta la. Duas
-- passadas para que o papel continuo (MRFG3 -> MBRF3) ganhe do incorporado
-- (BRFS3); o que sobrar de alias e duplicata e sai.
UPDATE ativo_monitorado a
JOIN ativo_identidade i ON i.simbolo = a.simbolo
SET a.simbolo = i.simbolo_canonico
WHERE i.simbolo <> i.simbolo_canonico AND i.continuidade_preco = 1
  AND i.simbolo_canonico NOT IN (SELECT s FROM (SELECT simbolo AS s FROM ativo_monitorado) t);

UPDATE ativo_monitorado a
JOIN ativo_identidade i ON i.simbolo = a.simbolo
SET a.simbolo = i.simbolo_canonico
WHERE i.simbolo <> i.simbolo_canonico AND i.continuidade_preco = 0
  AND i.simbolo_canonico NOT IN (SELECT s FROM (SELECT simbolo AS s FROM ativo_monitorado) t);

DELETE a FROM ativo_monitorado a
JOIN ativo_identidade i ON i.simbolo = a.simbolo
WHERE i.simbolo <> i.simbolo_canonico;

-- Indicadores gravados sob o codigo antigo: a proxima carga do ETL regrava
-- sob o canonico (com data_entrega), entao os antigos so atrapalham.
DELETE f FROM indicador_fundamentalista f
JOIN ativo_identidade i ON i.simbolo = f.simbolo
WHERE i.simbolo <> i.simbolo_canonico;

-- cotacao_atual e do JPA do gestor: pode nao existir num volume novo.
SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cotacao_atual'),
    'DELETE c FROM cotacao_atual c JOIN ativo_identidade i ON i.simbolo = c.simbolo WHERE i.simbolo <> i.simbolo_canonico',
    'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
