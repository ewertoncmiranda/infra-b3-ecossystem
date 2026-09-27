-- Formaliza no schema versionado as 4 tabelas de cache que ate aqui so
-- existiam por causa do Hibernate ddl-auto=update do gestor-ativos-brutos
-- (candle_diario, indice_macro, perfil_empresa_cache, cotacao_atual) - a
-- ultima parte da "fonte tripla de schema" que ainda faltava (mysql-init +
-- Hibernate; ativo_identidade/cotacao_b3_diaria/backtest_* ja tinham sido
-- resolvidas na V6).
--
-- Tipos e nomes de coluna copiados literalmente de SHOW CREATE TABLE contra
-- o banco vivo (nao adivinhados a partir das entidades JPA), pra garantir
-- que gestor-ativos-brutos rode sem gerar DDL nenhum quando
-- spring.jpa.hibernate.ddl-auto passar de "update" para "validate".
--
-- Idempotente: mysql-init de volume novo ja cria estas 4 tabelas: com
-- ddl-auto=validate, o Hibernate nunca mais precisa criar nada, so ler.

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
    -- Par preco anterior/atual (so anda quando o preco de fato muda - ver
    -- ServicoAtualizacaoCache.persistirCotacao no gestor-ativos-brutos).
    preco_anterior                 DECIMAL(38,2) NULL,
    preco_anterior_em              DATETIME(6)   NULL,
    preco_atual_desde              DATETIME(6)   NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cotacao_atual_simbolo (simbolo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
