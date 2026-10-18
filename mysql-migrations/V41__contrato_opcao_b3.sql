-- OPDB-INFRA-1: contrato de persistencia de opcoes alinhado ao ETL e ao gestor.
-- tipo_opcao e a classificacao semantica derivada de TPMERC (070=CALL, 080=PUT).
-- bdi permanece o CODBDI original do COTAHIST e nao determina o tipo.
-- INVALIDA e o status emitido pelo ETL para registros rejeitados; os estados
-- historicos existentes sao mantidos para compatibilidade de leitura.

ALTER TABLE opcao_b3_diaria
    DROP CHECK ck_opcao_b3_status,
    ADD CONSTRAINT ck_opcao_b3_status
        CHECK (status_validacao IN (
            'VALIDA',
            'INVALIDA',
            'REJEITADA',
            'INCOMPLETA',
            'LEGADO_NAO_VALIDADO'
        ));

ALTER TABLE opcao_b3_diaria
    MODIFY COLUMN bdi VARCHAR(2) NOT NULL
        COMMENT 'CODBDI original do COTAHIST; nao determina CALL/PUT';

CREATE OR REPLACE VIEW vw_opcao_b3_qualidade AS
SELECT
    COUNT(*) AS total_registros_opcoes,
    SUM(CASE WHEN status_validacao = 'VALIDA' THEN 1 ELSE 0 END) AS registros_validos,
    SUM(CASE WHEN status_validacao IN ('INVALIDA', 'REJEITADA') THEN 1 ELSE 0 END) AS registros_rejeitados,
    SUM(CASE WHEN status_validacao = 'INCOMPLETA' THEN 1 ELSE 0 END) AS registros_incompletos,
    SUM(CASE WHEN status_validacao = 'LEGADO_NAO_VALIDADO' THEN 1 ELSE 0 END) AS registros_legado_nao_validado,
    SUM(CASE WHEN data_vencimento = '9999-12-31' THEN 1 ELSE 0 END) AS registros_vencimento_9999,
    ROUND(
        100 * SUM(CASE WHEN status_validacao = 'VALIDA' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
        2
    ) AS percentual_valido,
    MAX(CASE WHEN status_validacao = 'VALIDA' THEN data_pregao ELSE NULL END) AS ultimo_pregao_com_opcoes_validas
FROM opcao_b3_diaria;

CREATE OR REPLACE VIEW vw_opcao_b3_qualidade_por_ativo AS
SELECT
    ativo_objeto,
    COUNT(*) AS total_registros_opcoes,
    SUM(CASE WHEN status_validacao = 'VALIDA' THEN 1 ELSE 0 END) AS registros_validos,
    SUM(CASE WHEN status_validacao IN ('INVALIDA', 'REJEITADA') THEN 1 ELSE 0 END) AS registros_rejeitados,
    SUM(CASE WHEN status_validacao = 'INCOMPLETA' THEN 1 ELSE 0 END) AS registros_incompletos,
    SUM(CASE WHEN status_validacao = 'LEGADO_NAO_VALIDADO' THEN 1 ELSE 0 END) AS registros_legado_nao_validado,
    SUM(CASE WHEN data_vencimento = '9999-12-31' THEN 1 ELSE 0 END) AS registros_vencimento_9999,
    ROUND(
        100 * SUM(CASE WHEN status_validacao = 'VALIDA' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
        2
    ) AS percentual_valido,
    MAX(CASE WHEN status_validacao = 'VALIDA' THEN data_pregao ELSE NULL END) AS ultimo_pregao_com_opcoes_validas
FROM opcao_b3_diaria
GROUP BY ativo_objeto;
