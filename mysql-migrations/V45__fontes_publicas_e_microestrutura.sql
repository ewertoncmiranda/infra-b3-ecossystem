-- CONS-INFRA-1: fontes publicas (Tesouro, IFData, CVM) e microestrutura B3
-- (datas ex e demais mercados do COTAHIST). Plano consolidado CONS (SPEC do hub).
-- Colunas CVM conforme cons-etl/docs/fontes/FONTES-ETL-1.md, secao
-- "Colunas finais para a V45". cvm_recompra e cvm_politica_dividendos sairam
-- do plano. Migration aditiva e idempotente: pode rodar duas vezes.

-- 1. Taxas e PUs dos titulos publicos (Tesouro Direto).
CREATE TABLE IF NOT EXISTS titulo_publico_taxa (
    id            BIGINT        NOT NULL AUTO_INCREMENT,
    tipo          VARCHAR(60)   NOT NULL,
    vencimento    DATE          NOT NULL,
    data_base     DATE          NOT NULL,
    taxa_compra   DECIMAL(9,4)  NULL,
    taxa_venda    DECIMAL(9,4)  NULL,
    pu_compra     DECIMAL(16,6) NULL,
    pu_venda      DECIMAL(16,6) NULL,
    pu_base       DECIMAL(16,6) NULL,
    criado_em     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_titulo_publico_taxa (tipo, vencimento, data_base),
    KEY idx_titulo_publico_taxa_data (data_base)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 2. Indicadores trimestrais de bancos (IFData/BCB).
CREATE TABLE IF NOT EXISTS banco_indicador_trimestral (
    id                       BIGINT        NOT NULL AUTO_INCREMENT,
    cnpj                     CHAR(14)      NOT NULL COMMENT 'Somente digitos',
    simbolo                  VARCHAR(12)   NULL,
    data_base                DATE          NOT NULL,
    basileia                 DECIMAL(9,4)  NULL,
    indice_capital_principal DECIMAL(9,4)  NULL,
    inadimplencia            DECIMAL(9,4)  NULL,
    roe                      DECIMAL(9,4)  NULL,
    ativo_total              DECIMAL(22,2) NULL,
    patrimonio_liquido       DECIMAL(22,2) NULL,
    carteira_credito         DECIMAL(22,2) NULL,
    origem                   VARCHAR(20)   NOT NULL DEFAULT 'IFDATA',
    criado_em                DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_banco_indicador_trimestral (cnpj, data_base)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 3. CVM: cadastro de companhias abertas (cad_cia_aberta).
CREATE TABLE IF NOT EXISTS cvm_cadastro (
    cnpj                CHAR(14)     NOT NULL COMMENT 'Somente digitos',
    codigo_cvm          VARCHAR(10)  NULL,
    denominacao         VARCHAR(200) NULL,
    situacao            VARCHAR(40)  NULL,
    data_situacao       DATE         NULL,
    data_cancelamento   DATE         NULL,
    motivo_cancelamento VARCHAR(200) NULL,
    setor_cvm           VARCHAR(120) NULL,
    situacao_emissor    VARCHAR(60)  NULL,
    controle_acionario  VARCHAR(40)  NULL,
    cnpj_auditor        CHAR(14)     NULL,
    auditor             VARCHAR(200) NULL,
    atualizado_em       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (cnpj),
    KEY idx_cvm_cadastro_codigo (codigo_cvm)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- CVM FRE: auditores (substitui o historico de auditor no cadastro).
CREATE TABLE IF NOT EXISTS cvm_auditor (
    id                         BIGINT       NOT NULL AUTO_INCREMENT,
    cnpj                       CHAR(14)     NOT NULL,
    data_referencia            DATE         NOT NULL,
    versao                     SMALLINT     NOT NULL,
    cnpj_auditor               CHAR(14)     NOT NULL,
    auditor                    VARCHAR(200) NULL,
    data_inicio                DATE         NOT NULL,
    data_fim                   DATE         NULL,
    justificativa_substituicao TEXT         NULL,
    criado_em                  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cvm_auditor (cnpj, data_referencia, cnpj_auditor, data_inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- CVM VLMO: negociacao de administradores e pessoas ligadas.
-- Nao ha identificador natural por linha: hash_linha (SHA-256 hex das colunas
-- de conteudo, calculado pelo ETL) evita duplicar no upsert.
CREATE TABLE IF NOT EXISTS cvm_negociacao_administrador (
    id                BIGINT        NOT NULL AUTO_INCREMENT,
    cnpj              CHAR(14)      NOT NULL,
    data_referencia   DATE          NOT NULL,
    versao            SMALLINT      NOT NULL,
    data_entrega      DATE          NULL,
    tipo_empresa      VARCHAR(60)   NULL,
    tipo_cargo        VARCHAR(120)  NULL,
    tipo_movimentacao VARCHAR(120)  NULL,
    tipo_operacao     VARCHAR(60)   NULL,
    tipo_ativo        VARCHAR(60)   NULL,
    caracteristica    VARCHAR(120)  NULL,
    data_movimentacao DATE          NULL,
    quantidade        DECIMAL(22,6) NULL,
    preco_unitario    DECIMAL(22,6) NULL,
    volume            DECIMAL(22,2) NULL,
    hash_linha        CHAR(64)      NOT NULL COMMENT 'SHA-256 hex das colunas de conteudo',
    criado_em         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cvm_negociacao_administrador (cnpj, data_referencia, versao, hash_linha),
    KEY idx_cvm_negociacao_admin_mov (cnpj, data_movimentacao)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- CVM FRE: dividas por valor mobiliario (antiga cvm_divida_vencimento).
CREATE TABLE IF NOT EXISTS cvm_divida_valor_mobiliario (
    id              BIGINT        NOT NULL AUTO_INCREMENT,
    cnpj            CHAR(14)      NOT NULL,
    data_referencia DATE          NOT NULL,
    versao          SMALLINT      NOT NULL,
    tipo            VARCHAR(100)  NULL,
    identificacao   VARCHAR(200)  NULL,
    data_emissao    DATE          NULL,
    data_vencimento DATE          NULL,
    quantidade      DECIMAL(22,6) NULL,
    valor           DECIMAL(22,2) NULL,
    saldo_devedor   DECIMAL(22,2) NULL,
    conversivel     VARCHAR(10)   NULL,
    hash_linha      CHAR(64)      NOT NULL COMMENT 'SHA-256 hex das colunas de conteudo',
    criado_em       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cvm_divida_valor_mobiliario (cnpj, data_referencia, versao, hash_linha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- CVM CDA: posicao de fundos em acoes.
CREATE TABLE IF NOT EXISTS fundo_posicao_acao (
    id            BIGINT        NOT NULL AUTO_INCREMENT,
    competencia   DATE          NOT NULL COMMENT 'Primeiro dia do mes',
    cnpj_fundo    CHAR(14)      NOT NULL,
    simbolo       VARCHAR(12)   NOT NULL,
    isin          VARCHAR(12)   NULL,
    quantidade    DECIMAL(22,6) NULL,
    valor_mercado DECIMAL(22,2) NULL,
    pl_fundo      DECIMAL(22,2) NULL,
    criado_em     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_fundo_posicao_acao (competencia, cnpj_fundo, simbolo),
    KEY idx_fundo_posicao_acao_simbolo (simbolo, competencia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 4. FII informe mensal: fora do escopo (DEC-FONTES-2, FIIs nao entram).

-- 5. Datas ex na B3 com ajuste implicito no preco.
CREATE TABLE IF NOT EXISTS data_ex_b3 (
    id                  BIGINT        NOT NULL AUTO_INCREMENT,
    simbolo             VARCHAR(12)   NOT NULL,
    data_ex             DATE          NOT NULL,
    marca               VARCHAR(4)    NOT NULL,
    tipo                VARCHAR(20)   NOT NULL,
    fechamento_anterior DECIMAL(14,4) NULL,
    abertura_ex         DECIMAL(14,4) NULL,
    ajuste_implicito    DECIMAL(14,4) NULL,
    ajuste_percentual   DECIMAL(9,4)  NULL,
    valor_declarado     DECIMAL(14,6) NULL,
    origem_valor        VARCHAR(30)   NULL,
    versao_calculo      VARCHAR(20)   NOT NULL,
    criado_em           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_data_ex_b3 (simbolo, data_ex, marca),
    KEY idx_data_ex_b3_data (data_ex),
    CONSTRAINT ck_data_ex_b3_tipo CHECK (tipo IN (
        'DIVIDENDO', 'JCP', 'RENDIMENTO', 'BONIFICACAO', 'SUBSCRICAO',
        'GRUPAMENTO', 'DESDOBRAMENTO', 'OUTRO'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 6. Demais mercados do COTAHIST (TPMERC fora de 010/070/080).
CREATE TABLE IF NOT EXISTS negociacao_b3_diaria (
    id                   BIGINT        NOT NULL AUTO_INCREMENT,
    simbolo              VARCHAR(12)   NOT NULL,
    simbolo_base         VARCHAR(12)   NULL,
    data_pregao          DATE          NOT NULL,
    tpmerc               CHAR(3)       NOT NULL,
    codbdi               CHAR(2)       NULL,
    especificacao        VARCHAR(10)   NULL,
    prazo_termo_dias     INT           NULL,
    indice_correcao      CHAR(1)       NULL,
    preco_exercicio      DECIMAL(14,4) NULL,
    data_vencimento      DATE          NULL,
    abertura             DECIMAL(14,4) NULL,
    maxima               DECIMAL(14,4) NULL,
    minima               DECIMAL(14,4) NULL,
    fechamento           DECIMAL(14,4) NULL,
    preco_medio          DECIMAL(14,4) NULL,
    melhor_oferta_compra DECIMAL(14,4) NULL,
    melhor_oferta_venda  DECIMAL(14,4) NULL,
    volume               BIGINT        NULL,
    numero_negocios      INT           NULL,
    volume_financeiro    DECIMAL(22,2) NULL,
    fator_cotacao        INT           NULL,
    isin                 VARCHAR(12)   NULL,
    dismes               SMALLINT      NULL,
    criado_em            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_negociacao_b3_diaria (simbolo, data_pregao, tpmerc),
    KEY idx_negociacao_b3_diaria_base (simbolo_base, data_pregao),
    CONSTRAINT ck_negociacao_b3_diaria_tpmerc CHECK (tpmerc IN (
        '012', '013', '017', '020', '030', '050', '060'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 7. Novas etapas de carga. DROP + ADD condicionais via information_schema.
SET @ck_existe = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'carga_etapa'
                    AND CONSTRAINT_NAME = 'ck_carga_etapa_etapa' AND CONSTRAINT_TYPE = 'CHECK');
SET @sql = IF(@ck_existe > 0, 'ALTER TABLE carga_etapa DROP CHECK ck_carga_etapa_etapa', 'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
ALTER TABLE carga_etapa ADD CONSTRAINT ck_carga_etapa_etapa CHECK (etapa IN (
    'COTAHIST', 'LIQUIDEZ', 'PRONTIDAO', 'QUALIDADE_OPCOES', 'CONCILIACAO',
    'DFP', 'TTM', 'IPE', 'DVA', 'EVENTOS', 'CHECAGENS',
    'TESOURO', 'IFDATA', 'CVM_CADASTRO', 'CVM_VLMO', 'CVM_FRE', 'CVM_CDA'));

-- 8. etl_execucao aceita INCOMPLETO (o ETL ja grava esse status).
SET @ck_existe = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'etl_execucao'
                    AND CONSTRAINT_NAME = 'chk_etl_execucao_status' AND CONSTRAINT_TYPE = 'CHECK');
SET @sql = IF(@ck_existe > 0, 'ALTER TABLE etl_execucao DROP CHECK chk_etl_execucao_status', 'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
ALTER TABLE etl_execucao ADD CONSTRAINT chk_etl_execucao_status
    CHECK (status IN ('EM_ANDAMENTO', 'SUCESSO', 'PULADO', 'ERRO', 'INCOMPLETO'));
