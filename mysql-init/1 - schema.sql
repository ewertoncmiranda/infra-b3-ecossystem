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
        CHECK (tipo_doc IN ('DFP', 'ITR', 'TTM')),
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
    -- DT_RECEB da CVM: quando o balanco ficou publico (point-in-time, V6)
    data_entrega DATE NULL,

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
    INDEX idx_indicador_simbolo_entrega (simbolo, data_entrega),

    CONSTRAINT chk_indicador_tipo_periodo
        CHECK (tipo_periodo IN ('ANUAL', 'TRIMESTRAL', 'TTM')),
    CONSTRAINT chk_indicador_tipo_doc
        CHECK (tipo_doc IN ('DFP', 'ITR', 'TTM'))
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

-- Diario de sinais (paper trading). Mesmo DDL de mysql-migrations/V4__diario_de_sinais.sql,
-- repetido aqui para volume novo ja nascer com as tabelas. Contrato: CTR-11.
CREATE TABLE IF NOT EXISTS sinal_diario (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(10) NOT NULL,
    data_pregao DATE NOT NULL,
    versao_regra VARCHAR(20) NOT NULL,

    recomendacao VARCHAR(20) NOT NULL,
    nivel_risco VARCHAR(10) NULL,
    confianca_score SMALLINT NULL,
    sinal_momentum VARCHAR(20) NULL,
    sinal_reversao VARCHAR(20) NULL,

    -- Fechamento oficial do pregao do sinal (candle_diario), para referencia.
    -- A avaliacao entra na ABERTURA do pregao seguinte, nao neste preco.
    preco_fechamento DECIMAL(12,4) NOT NULL,
    insight_id INT NOT NULL,
    registrado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_sinal_diario (simbolo, data_pregao, versao_regra),
    INDEX idx_sinal_diario_data (data_pregao),
    INDEX idx_sinal_diario_versao (versao_regra, recomendacao)
);

CREATE TABLE IF NOT EXISTS sinal_resultado (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sinal_id BIGINT NOT NULL,
    horizonte SMALLINT NOT NULL,

    data_entrada DATE NOT NULL,
    data_saida DATE NOT NULL,
    preco_entrada DECIMAL(12,4) NOT NULL,
    preco_saida DECIMAL(12,4) NOT NULL,

    retorno_bruto DECIMAL(12,6) NOT NULL,
    retorno_liquido DECIMAL(12,6) NOT NULL,
    -- Benchmark de mercado: media simples da carteira monitorada no mesmo
    -- periodo (V5 trocou o BOVA11, que nao e coletado).
    retorno_carteira DECIMAL(12,6) NULL,
    retorno_cdi DECIMAL(12,6) NULL,
    excesso_carteira DECIMAL(12,6) NULL,
    ativos_na_carteira SMALLINT NULL,
    excesso_cdi DECIMAL(12,6) NULL,

    -- NULL = recomendacao sem direcao (MANTER, ALERTA_RISCO): nao ha aposta
    acerto BOOLEAN NULL,
    -- Salto >= 40% entre pregoes na janela: provavel desdobramento/grupamento
    -- em preco bruto; fica fora das estatisticas
    evento_suspeito BOOLEAN NOT NULL DEFAULT FALSE,
    avaliado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_sinal_resultado (sinal_id, horizonte),
    CONSTRAINT fk_sinal_resultado_sinal
        FOREIGN KEY (sinal_id) REFERENCES sinal_diario (id)
);

-- Identidade canonica, COTAHIST oficial e backtest (V6; CTR-12..14).
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
    -- intervalo de confianca (V9, TASK-30)
    n_excesso_cdi          INT           NULL,
    desvio_excesso_cdi     DECIMAL(12,6) NULL,
    n_excesso_carteira     INT           NULL,
    desvio_excesso_carteira DECIMAL(12,6) NULL,
    -- janelas com retorno ajustado por provento (V10, TASK-36)
    janelas_com_provento   INT           NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_backtest_placar (execucao_id, versao_regra, periodo, recomendacao, horizonte),
    CONSTRAINT fk_backtest_placar_execucao FOREIGN KEY (execucao_id)
        REFERENCES backtest_execucao (id) ON DELETE CASCADE,
    CONSTRAINT chk_backtest_placar_periodo CHECK (periodo IN ('CALIBRACAO', 'TESTE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Cache do gestor-ativos-brutos (BRAPI + perfil da empresa): ate aqui so
-- existiam por causa do Hibernate ddl-auto=update, nao daqui. Formalizadas
-- tambem em mysql-migrations/V7 para quem sobe a partir de um volume ja
-- existente. Tipos copiados de SHOW CREATE TABLE contra o banco vivo.
CREATE TABLE IF NOT EXISTS candle_diario (
    id              BIGINT        NOT NULL AUTO_INCREMENT,
    simbolo         VARCHAR(10)   NOT NULL,
    data            DATE          NOT NULL,
    open            DECIMAL(12,4) NULL,
    high            DECIMAL(12,4) NULL,
    low             DECIMAL(12,4) NULL,
    close           DECIMAL(12,4) NULL,
    volume          DECIMAL(38,2) NULL,
    adjusted_close  DECIMAL(12,4) NULL,
    atualizado_em   DATETIME(6)   NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_candle_diario_simbolo_data (simbolo, data)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS indice_macro (
    id             BIGINT        NOT NULL AUTO_INCREMENT,
    codigo_serie   VARCHAR(20)   NOT NULL,
    data           DATE          NOT NULL,
    valor          DECIMAL(12,6) NULL,
    atualizado_em  DATETIME(6)   NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_indice_macro_codigo_data (codigo_serie, data)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS perfil_empresa_cache (
    id                     BIGINT       NOT NULL AUTO_INCREMENT,
    simbolo                VARCHAR(10)  NOT NULL,
    sector                 VARCHAR(255) NULL,
    industry               VARCHAR(255) NULL,
    long_business_summary  TEXT         NULL,
    website                VARCHAR(255) NULL,
    cnpj                   VARCHAR(255) NULL,
    full_time_employees    INT          NULL,
    city                   VARCHAR(255) NULL,
    state                  VARCHAR(255) NULL,
    atualizado_em          DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_perfil_empresa_cache_simbolo (simbolo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS cotacao_atual (
    id                             BIGINT        NOT NULL AUTO_INCREMENT,
    simbolo                        VARCHAR(10)   NOT NULL,
    short_name                     VARCHAR(255)  NULL,
    long_name                      VARCHAR(255)  NULL,
    market_cap                     DECIMAL(38,2) NULL,
    regular_market_change          DECIMAL(38,2) NULL,
    regular_market_change_percent  DECIMAL(38,2) NULL,
    regular_market_time            VARCHAR(255)  NULL,
    regular_market_price           DECIMAL(38,2) NULL,
    regular_market_day_high        DECIMAL(38,2) NULL,
    regular_market_day_low         DECIMAL(38,2) NULL,
    regular_market_volume          DECIMAL(38,2) NULL,
    regular_market_previous_close  DECIMAL(38,2) NULL,
    regular_market_open            DECIMAL(38,2) NULL,
    fifty_two_week_low             DECIMAL(38,2) NULL,
    fifty_two_week_high            DECIMAL(38,2) NULL,
    price_earnings                 DECIMAL(38,2) NULL,
    earnings_per_share             DECIMAL(38,2) NULL,
    atualizado_em                  DATETIME(6)   NOT NULL,
    preco_anterior                 DECIMAL(38,2) NULL,
    preco_anterior_em              DATETIME(6)   NULL,
    preco_atual_desde              DATETIME(6)   NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cotacao_atual_simbolo (simbolo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Cache de proventos por emissora (B3 GetListedSupplementCompany) - ver
-- mysql-migrations/V8 pro detalhe e a limitacao de janela de 12 meses.
CREATE TABLE IF NOT EXISTS provento_distribuido (
    id                       BIGINT         NOT NULL AUTO_INCREMENT,
    simbolo                  VARCHAR(10)    NOT NULL,
    isin                     VARCHAR(20)    NOT NULL,
    tipo                     VARCHAR(30)    NOT NULL,
    valor_por_acao           DECIMAL(14,8)  NOT NULL,
    periodo_referencia       VARCHAR(30)    NULL,
    aprovado_em              DATE           NULL,
    ultima_data_com_direito  DATE           NULL,
    data_pagamento           DATE           NOT NULL,
    atualizado_em            DATETIME(6)    NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_provento_distribuido (simbolo, isin, tipo, data_pagamento),
    INDEX idx_provento_distribuido_simbolo (simbolo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
