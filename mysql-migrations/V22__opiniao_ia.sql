-- Opiniao por horizonte (curto 21, medio 63, longo 126 pregoes), gerada pelo gerar-insights
-- (`python -m app.opiniao.gerar`) a partir do insight deterministico, com um modelo local (Ollama)
-- restrito ao dossie de evidencias. Rotulos NEUTROS: SINAL_POSITIVO, SINAL_NEGATIVO, SINAL_NEUTRO,
-- SEM_BASE. Regra experimental: nenhuma linha daqui e recomendacao de investimento.
--
-- SO INSERCAO, como sinal_diario: a opiniao de um dia nunca e reescrita, para o diario poder
-- medi-la depois sem olhar o futuro. Mudou modelo ou prompt = linha nova (chave unica abaixo).

CREATE TABLE IF NOT EXISTS opiniao_ia (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    simbolo VARCHAR(10) NOT NULL,
    data_pregao DATE NOT NULL,
    horizonte_pregoes SMALLINT NOT NULL,

    opiniao VARCHAR(20) NOT NULL,
    risco VARCHAR(20) NOT NULL,

    -- [{evidencia_id, leitura}], [texto], [texto], [{id, rotulo, valor, direcao}]
    justificativa_json JSON NOT NULL,
    invalida_json JSON NOT NULL,
    dados_ausentes_json JSON NOT NULL,
    evidencias_json JSON NOT NULL,

    modelo VARCHAR(60) NOT NULL,           -- nome do modelo, ou 'regra' quando nao houve modelo
    versao_prompt VARCHAR(20) NOT NULL,
    versao_regra VARCHAR(20) NULL,         -- versao da regra deterministica do insight de origem
    origem VARCHAR(10) NOT NULL,           -- MODELO | REGRA (resposta rejeitada ou SEM_BASE forcado)
    tentativas SMALLINT NOT NULL DEFAULT 0,
    dossie_hash CHAR(64) NOT NULL,
    insight_id INT NULL,

    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_opiniao_ia UNIQUE (simbolo, data_pregao, horizonte_pregoes, modelo, versao_prompt),
    CONSTRAINT ck_opiniao_ia_opiniao CHECK (opiniao IN ('SINAL_POSITIVO','SINAL_NEGATIVO','SINAL_NEUTRO','SEM_BASE')),
    CONSTRAINT ck_opiniao_ia_risco CHECK (risco IN ('RISCO_BAIXO','RISCO_MEDIO','RISCO_ALTO')),
    CONSTRAINT ck_opiniao_ia_origem CHECK (origem IN ('MODELO','REGRA')),
    INDEX idx_opiniao_ia_ativo (simbolo, data_pregao)
);
