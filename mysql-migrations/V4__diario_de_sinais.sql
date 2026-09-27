-- Diario de sinais (paper trading): um sinal por ativo por pregao por versao
-- de regra, gravado depois do fechamento, e o resultado de cada horizonte
-- preenchido quando ele vence. Escrito pelo gerar-insights
-- (`python -m app.validacao.diario`). Contrato: CTR-11.
--
-- sinal_diario e SO INSERCAO: um sinal registrado nunca e alterado. Corrigir
-- o passado com informacao que so existiu depois e exatamente o viés que o
-- diario existe para evitar. Regra nova = versao_regra nova = linha nova.

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
    retorno_bova11 DECIMAL(12,6) NULL,
    retorno_cdi DECIMAL(12,6) NULL,
    excesso_bova11 DECIMAL(12,6) NULL,
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
