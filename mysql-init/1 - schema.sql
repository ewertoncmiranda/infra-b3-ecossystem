-- Tabela de histórico de ativos
CREATE TABLE IF NOT EXISTS historico_acoes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    dedup_key VARCHAR(64),

    simbolo VARCHAR(10) NOT NULL,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    preco_abertura DECIMAL(12,4),
    preco_fechamento DECIMAL(12,4),
    preco_maximo DECIMAL(12,4),
    preco_minimo DECIMAL(12,4),

    volume BIGINT,

    minima_52_semanas DECIMAL(12,4),
    maxima_52_semanas DECIMAL(12,4),

    valor_mercado BIGINT,
    preco_lucro DECIMAL(10,4),
    lucro_por_acao DECIMAL(10,4),

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Índices para melhor performance
    INDEX idx_simbolo (simbolo),
    INDEX idx_timestamp (timestamp),
    INDEX idx_simbolo_timestamp (simbolo, timestamp),
    UNIQUE KEY uq_historico_acoes_dedup_key (dedup_key)
);

-- Tabela de insights extraídos das análises
CREATE TABLE IF NOT EXISTS insight_acao (
    id INT AUTO_INCREMENT PRIMARY KEY,
    dedup_key VARCHAR(64),
    simbolo VARCHAR(10) NOT NULL,
    data_analise DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    preco_justo_graham DECIMAL(12,4),
    margem_seguranca_percent DECIMAL(10,4),
    recomendacao VARCHAR(20),
    detalhes_json JSON,

    INDEX idx_simbolo_insight (simbolo),
    INDEX idx_data_analise (data_analise),
    UNIQUE KEY uq_insight_acao_dedup_key (dedup_key)
);

-- Tabela de candles diarios de series historicas
CREATE TABLE IF NOT EXISTS serie_historica (
    id INT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(10) NOT NULL,
    data_pregao DATE NOT NULL,
    intervalo VARCHAR(10) NOT NULL DEFAULT '1d',
    range_usado VARCHAR(10),

    abertura DECIMAL(12,4),
    maxima DECIMAL(12,4),
    minima DECIMAL(12,4),
    fechamento DECIMAL(12,4),
    fechamento_ajustado DECIMAL(12,4),
    volume BIGINT,

    fonte VARCHAR(30) NOT NULL DEFAULT 'BRAPI',
    detalhes_json JSON,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_serie_historica_dia (simbolo, data_pregao, intervalo),
    INDEX idx_serie_historica_simbolo (simbolo),
    INDEX idx_serie_historica_data (data_pregao),
    INDEX idx_serie_historica_simbolo_data (simbolo, data_pregao)
);

-- Ativos configurados para monitoramento recorrente
CREATE TABLE IF NOT EXISTS ativo_monitorado (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(10) NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    tipo_coleta VARCHAR(30) NOT NULL DEFAULT 'COTACAO',
    intervalo_segundos INT UNSIGNED NOT NULL DEFAULT 300,

    versao BIGINT NOT NULL DEFAULT 0,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_ativo_monitorado_simbolo (simbolo),
    INDEX idx_ativo_monitorado_status_atualizacao (ativo, atualizado_em),

    CONSTRAINT chk_ativo_monitorado_intervalo
        CHECK (intervalo_segundos >= 30),
    CONSTRAINT chk_ativo_monitorado_tipo
        CHECK (tipo_coleta IN ('COTACAO', 'COTACAO_E_HISTORICO'))
);

-- ============================================================================
-- Fundamentos CVM (dados abertos)
--
-- Alimentado pelo job em lote etl-fundamentos-cvm, que le os ZIPs de
-- dados.cvm.gov.br (DFP anual, ITR trimestral, FCA cadastral).
--
-- Duas camadas:
--   fato_contabil             -> landing das contas cruas ja normalizadas
--   indicador_fundamentalista -> mart consumido pelo gerar-insights
--
-- Somente indicador_fundamentalista e contrato de leitura para as aplicacoes.
-- ============================================================================

-- Companhias abertas (origem: FCA)
CREATE TABLE IF NOT EXISTS cvm_empresa (
    cnpj VARCHAR(20) PRIMARY KEY,

    cd_cvm VARCHAR(10),
    denominacao VARCHAR(200) NOT NULL,
    setor VARCHAR(60),

    -- Bancos e seguradoras usam plano de contas proprio: no BB a conta 3.01 e
    -- "Receitas de Intermediacao Financeira", na WEG e "Receita de Venda".
    -- O de-para consulta este campo antes de mapear receita, EBIT e margens.
    plano_contas VARCHAR(20) NOT NULL DEFAULT 'GERAL',

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_cvm_empresa_cd_cvm (cd_cvm),

    CONSTRAINT chk_cvm_empresa_plano
        CHECK (plano_contas IN ('GERAL', 'FINANCEIRO', 'SEGURADORA'))
);

-- Tickers negociados na B3 por companhia (origem: FCA valor_mobiliario)
CREATE TABLE IF NOT EXISTS cvm_ticker (
    simbolo VARCHAR(10) PRIMARY KEY,

    cnpj VARCHAR(20) NOT NULL,
    tipo_valor_mobiliario VARCHAR(60),
    mercado VARCHAR(40),
    ativo BOOLEAN NOT NULL DEFAULT TRUE,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_cvm_ticker_cnpj (cnpj),

    CONSTRAINT fk_cvm_ticker_empresa
        FOREIGN KEY (cnpj) REFERENCES cvm_empresa (cnpj)
        ON DELETE CASCADE
);

-- Landing das contas contabeis.
-- Carregada apenas com a whitelist de CD_CONTA usada pelo de-para (o DMPL
-- inteiro passa de 58 MB/ano e nao e consumido).
--
-- Normalizacoes aplicadas na carga:
--   - so linhas com ORDEM_EXERC = 'ULTIMO' (PENULTIMO duplicaria o exercicio)
--   - vl_conta ja convertido para reais (ESCALA_MOEDA = MIL implica x1000)
--   - dt_ini_exerc recebe dt_fim_exerc nas contas de balanco (BPA/BPP), que
--     nao possuem periodo inicial, para manter a unique key deterministica
CREATE TABLE IF NOT EXISTS fato_contabil (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    cnpj VARCHAR(20) NOT NULL,
    tipo_doc VARCHAR(5) NOT NULL,
    grupo VARCHAR(3) NOT NULL,
    demonstracao VARCHAR(10) NOT NULL,

    dt_refer DATE NOT NULL,
    dt_ini_exerc DATE NOT NULL,
    dt_fim_exerc DATE NOT NULL,
    versao SMALLINT UNSIGNED NOT NULL,

    cd_conta VARCHAR(20) NOT NULL,
    ds_conta VARCHAR(200),
    vl_conta DECIMAL(24,2) NOT NULL,

    -- ST_CONTA_FIXA='S' marca conta padronizada pela CVM. E por este flag, e
    -- nao pelo CD_CONTA, que o de-para localiza as contas: "Patrimonio Liquido
    -- Consolidado" e 2.03 na WEG, 2.07 no BBAS3 e 2.08 no ITUB4, mas sempre
    -- ST_CONTA_FIXA='S' com a mesma descricao.
    conta_fixa BOOLEAN NOT NULL DEFAULT FALSE,
    ds_conta_norm VARCHAR(200),

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_fato_contabil (
        cnpj, tipo_doc, grupo, demonstracao, dt_fim_exerc, dt_ini_exerc, cd_conta
    ),
    INDEX idx_fato_contabil_cnpj_periodo (cnpj, dt_fim_exerc),
    INDEX idx_fato_contabil_conta (cd_conta),
    INDEX idx_fato_contabil_resolucao (cnpj, dt_fim_exerc, demonstracao, conta_fixa),

    CONSTRAINT chk_fato_contabil_tipo_doc
        CHECK (tipo_doc IN ('DFP', 'ITR')),
    CONSTRAINT chk_fato_contabil_grupo
        CHECK (grupo IN ('con', 'ind'))
);

-- Quantidade de acoes por competencia (origem: composicao_capital).
-- Separada de fato_contabil porque nao e conta contabil e e o denominador
-- de LPA e VPA.
CREATE TABLE IF NOT EXISTS cvm_composicao_capital (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    cnpj VARCHAR(20) NOT NULL,
    dt_refer DATE NOT NULL,
    tipo_doc VARCHAR(5) NOT NULL,
    versao SMALLINT UNSIGNED NOT NULL,

    qt_acao_ordinaria BIGINT NOT NULL DEFAULT 0,
    qt_acao_preferencial BIGINT NOT NULL DEFAULT 0,
    qt_acao_total BIGINT NOT NULL DEFAULT 0,
    qt_acao_tesouraria BIGINT NOT NULL DEFAULT 0,
    qt_acao_ex_tesouraria BIGINT NOT NULL DEFAULT 0,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_cvm_composicao_capital (cnpj, dt_refer, tipo_doc),

    CONSTRAINT chk_cvm_composicao_tipo_doc
        CHECK (tipo_doc IN ('DFP', 'ITR'))
);

-- Mart de indicadores. Unico contrato de leitura para gerar-insights.
--
-- Metricas que o plano de contas da companhia nao suporta ficam NULL e a
-- razao vai em cobertura_json: melhor ausencia explicita que numero errado.
CREATE TABLE IF NOT EXISTS indicador_fundamentalista (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(10) NOT NULL,
    cnpj VARCHAR(20) NOT NULL,
    periodo DATE NOT NULL,
    tipo_periodo VARCHAR(12) NOT NULL DEFAULT 'ANUAL',

    -- insumos
    lucro_liquido DECIMAL(24,2),
    patrimonio_liquido DECIMAL(24,2),

    -- LPA, VPA e ROE sao calculados sobre a parcela do controlador, que e a
    -- convencao que Fundamentus e StatusInvest publicam. Sem separar, a WEG
    -- sai com ROE 36,5% contra 33,2% das referencias - diferenca de
    -- participacao de terceiros, nao erro de conta.
    lucro_liquido_controlador DECIMAL(24,2),
    participacao_nao_controladores DECIMAL(24,2),

    receita_liquida DECIMAL(24,2),
    ebit DECIMAL(24,2),
    divida_bruta DECIMAL(24,2),
    caixa_equivalentes DECIMAL(24,2),
    fluxo_caixa_operacional DECIMAL(24,2),
    capex DECIMAL(24,2),
    acoes_ex_tesouraria BIGINT,

    -- derivados
    lpa DECIMAL(18,6),
    vpa DECIMAL(18,6),
    roe DECIMAL(10,4),
    roic DECIMAL(10,4),
    margem_liquida DECIMAL(10,4),
    divida_liquida DECIMAL(24,2),
    fluxo_caixa_livre DECIMAL(24,2),

    -- procedencia
    fonte VARCHAR(20) NOT NULL DEFAULT 'CVM',
    tipo_doc VARCHAR(5) NOT NULL,
    grupo VARCHAR(3) NOT NULL DEFAULT 'con',
    versao_cvm SMALLINT UNSIGNED NOT NULL,
    plano_contas VARCHAR(20) NOT NULL DEFAULT 'GERAL',
    cobertura_json JSON,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_indicador_fundamentalista (simbolo, periodo, tipo_periodo),
    INDEX idx_indicador_simbolo (simbolo),
    INDEX idx_indicador_cnpj_periodo (cnpj, periodo),
    INDEX idx_indicador_simbolo_periodo (simbolo, periodo),

    CONSTRAINT chk_indicador_tipo_periodo
        CHECK (tipo_periodo IN ('ANUAL', 'TRIMESTRAL', 'TTM')),
    CONSTRAINT chk_indicador_tipo_doc
        CHECK (tipo_doc IN ('DFP', 'ITR'))
);

-- Log append-only das execucoes do ETL.
-- O job consulta a ultima linha SUCESSO de cada (fonte, competencia, arquivo)
-- e compara o ETag por HEAD antes de baixar: inalterado, pula o download.
CREATE TABLE IF NOT EXISTS etl_execucao (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    fonte VARCHAR(40) NOT NULL,
    competencia VARCHAR(10) NOT NULL,
    arquivo VARCHAR(200) NOT NULL,

    etag VARCHAR(200),
    last_modified VARCHAR(80),
    tamanho_bytes BIGINT,

    status VARCHAR(20) NOT NULL,
    linhas_carregadas INT NOT NULL DEFAULT 0,
    mensagem_erro TEXT,

    iniciado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finalizado_em DATETIME NULL,

    INDEX idx_etl_execucao_lookup (fonte, competencia, arquivo, status, finalizado_em),
    INDEX idx_etl_execucao_iniciado (iniciado_em),

    CONSTRAINT chk_etl_execucao_status
        CHECK (status IN ('EM_ANDAMENTO', 'SUCESSO', 'PULADO', 'ERRO'))
);

-- Comunicados oficiais da base IPE da CVM (fatos relevantes, comunicados ao
-- mercado, proventos...). Mesmo DDL de mysql-migrations/V3__comunicados_cvm.sql,
-- repetido aqui para volume novo ja nascer com a tabela. Contrato: CTR-08.
-- Chave natural: numProtocolo do link de download (Protocolo_Entrega vem
-- vazio nos relatorios automaticos de proventos). Guarda CNPJ, nao ticker:
-- a traducao e feita na leitura via cvm_ticker.
CREATE TABLE IF NOT EXISTS comunicado_cvm (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    protocolo_cvm VARCHAR(20) NOT NULL,
    protocolo_entrega VARCHAR(40) NULL,
    versao SMALLINT NOT NULL DEFAULT 1,

    cnpj VARCHAR(20) NOT NULL,
    codigo_cvm VARCHAR(10) NULL,

    categoria VARCHAR(40) NOT NULL,
    categoria_original VARCHAR(200) NOT NULL,
    tipo VARCHAR(120) NULL,
    especie VARCHAR(120) NULL,
    assunto TEXT NULL,

    data_referencia DATE NULL,
    data_entrega DATE NOT NULL,
    link_download VARCHAR(300) NOT NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_comunicado_cvm_protocolo (protocolo_cvm),
    INDEX idx_comunicado_cvm_cnpj_data (cnpj, data_entrega),
    INDEX idx_comunicado_cvm_categoria_data (categoria, data_entrega),
    INDEX idx_comunicado_cvm_data (data_entrega),
    FULLTEXT KEY ft_comunicado_cvm_assunto (assunto)
);
