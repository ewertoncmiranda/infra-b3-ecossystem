-- OPRV2-INFRA-2: compatibilidade da projecao com gerar-insights OPRV2-INS-1..4.
-- V25 permanece imutavel; V26 acrescenta campos indexaveis e preserva payload_json completo.

ALTER TABLE ticker_operacional_snapshot
    ADD COLUMN status_operacional VARCHAR(25) NULL AFTER status_sistema,
    ADD COLUMN setor_grupo VARCHAR(60) NULL AFTER faixa_liquidez,
    ADD COLUMN sinal_principal VARCHAR(40) NULL AFTER setor_grupo,
    ADD COLUMN sinal_tecnico JSON NULL AFTER sinal_principal,
    ADD COLUMN opiniao_ia VARCHAR(40) NULL AFTER sinal_tecnico,
    ADD COLUMN confianca_faixa VARCHAR(20) NULL AFTER opiniao_ia,
    ADD COLUMN posicao_status VARCHAR(12) NULL AFTER confianca_faixa,
    ADD COLUMN ultimo_evento_tipo VARCHAR(30) NULL AFTER posicao_status,
    ADD COLUMN consenso_json JSON NULL AFTER payload_json,
    ADD COLUMN tese_json JSON NULL AFTER consenso_json,
    ADD CONSTRAINT ck_ticker_snapshot_status_operacional CHECK (status_operacional IS NULL OR status_operacional IN
        ('NAO_OPERAVEL','EM_OBSERVACAO','PAPER_TRADING_ELEGIVEL','BLOQUEADO')),
    ADD CONSTRAINT ck_ticker_snapshot_confianca CHECK (confianca_faixa IS NULL OR confianca_faixa IN
        ('ALTA','MEDIA','BAIXA','NAO_CALIBRADA')),
    ADD INDEX idx_ticker_snapshot_status_liquidez (status_operacional, faixa_liquidez),
    ADD INDEX idx_ticker_snapshot_sinal_confianca (sinal_principal, confianca_faixa),
    ADD INDEX idx_ticker_snapshot_setor (setor_grupo);

ALTER TABLE ticker_operacional_timeline
    ADD COLUMN data_evento DATE NULL AFTER data_pregao,
    ADD COLUMN versao_regra VARCHAR(30) NULL AFTER data_evento,
    ADD COLUMN tipo VARCHAR(30) NULL AFTER tipo_evento,
    ADD COLUMN titulo VARCHAR(500) NULL AFTER codigo,
    DROP CHECK ck_ticker_timeline_tipo,
    ADD CONSTRAINT ck_ticker_timeline_tipo CHECK (tipo_evento IN
        ('SINAL_ALTERADO','SINAL_GERADO','POSICAO_ABERTA','POSICAO_FECHADA','BLOQUEIO',
         'BLOQUEIO_DADO','BLOQUEIO_LIQUIDEZ','EVENTO_CVM','PROVENTO','SALTO_PRECO',
         'CONFIANCA_ALTERADA','STATUS_ALTERADO','DIARIO_AVALIADO','ALERTA','ALERTA_RISCO')),
    ADD INDEX idx_ticker_timeline_versao_data (versao_regra, data_evento),
    ADD INDEX idx_ticker_timeline_tipo (tipo, severidade, data_evento);

UPDATE ticker_operacional_timeline
SET data_evento = data_pregao,
    tipo = tipo_evento,
    titulo = codigo
WHERE data_evento IS NULL OR tipo IS NULL OR titulo IS NULL;
