-- Tabela de histórico de ativos
CREATE TABLE IF NOT EXISTS historico_acoes (
    id INT AUTO_INCREMENT PRIMARY KEY,

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
    INDEX idx_simbolo_timestamp (simbolo, timestamp)
);

-- Tabela de insights extraídos das análises
CREATE TABLE IF NOT EXISTS insight_acao (
    id INT AUTO_INCREMENT PRIMARY KEY,
    simbolo VARCHAR(10) NOT NULL,
    data_analise DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    preco_justo_graham DECIMAL(12,4),
    margem_seguranca_percent DECIMAL(10,4),
    recomendacao VARCHAR(20),
    detalhes_json JSON,

    INDEX idx_simbolo_insight (simbolo),
    INDEX idx_data_analise (data_analise)
);
