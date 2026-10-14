-- V30__opcao_b3_diaria_validacao.sql
-- OPT-INFRA-1: contrato mínimo para diferenciar cadeia de opções válida,
-- registros rejeitados e legado ainda não validado.
--
-- A tabela existente foi preservada para não perder histórico. Dados já
-- carregados passam a nascer como LEGADO_NAO_VALIDADO até a etapa do ETL
-- reprocessar/classificar pelo layout correto do COTAHIST.

ALTER TABLE opcao_b3_diaria
    ADD COLUMN ativo_objeto VARCHAR(12) NULL
        COMMENT 'Ticker canonico do ativo-objeto da opcao, quando validada pelo ETL',
    ADD COLUMN tipo_opcao VARCHAR(4) NULL
        COMMENT 'CALL ou PUT quando o instrumento for uma opcao real',
    ADD COLUMN status_validacao VARCHAR(30) NOT NULL DEFAULT 'LEGADO_NAO_VALIDADO'
        COMMENT 'VALIDA, REJEITADA, INCOMPLETA ou LEGADO_NAO_VALIDADO',
    ADD COLUMN motivo_rejeicao VARCHAR(80) NULL
        COMMENT 'Motivo estruturado para registros rejeitados ou incompletos';

ALTER TABLE opcao_b3_diaria
    ADD CONSTRAINT ck_opcao_b3_tipo
        CHECK (tipo_opcao IS NULL OR tipo_opcao IN ('CALL', 'PUT')),
    ADD CONSTRAINT ck_opcao_b3_status
        CHECK (status_validacao IN ('VALIDA', 'REJEITADA', 'INCOMPLETA', 'LEGADO_NAO_VALIDADO'));

CREATE INDEX idx_opcao_b3_ativo_pregao_vencimento_tipo
    ON opcao_b3_diaria (ativo_objeto, data_pregao, data_vencimento, tipo_opcao);

CREATE INDEX idx_opcao_b3_status_validacao
    ON opcao_b3_diaria (status_validacao, motivo_rejeicao);
