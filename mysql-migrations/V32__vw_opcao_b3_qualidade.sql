-- V32__vw_opcao_b3_qualidade.sql
-- OPT-INFRA-3: consultas de observabilidade para qualidade da cadeia de opcoes.
--
-- O gestor pode usar estas views como fonte estavel para /opcoes/saude
-- sem replicar regras agregadas em cada consumidor.

CREATE OR REPLACE VIEW vw_opcao_b3_qualidade AS
SELECT
    COUNT(*) AS total_registros_opcoes,
    SUM(CASE WHEN status_validacao = 'VALIDA' THEN 1 ELSE 0 END) AS registros_validos,
    SUM(CASE WHEN status_validacao = 'REJEITADA' THEN 1 ELSE 0 END) AS registros_rejeitados,
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
    SUM(CASE WHEN status_validacao = 'REJEITADA' THEN 1 ELSE 0 END) AS registros_rejeitados,
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

CREATE OR REPLACE VIEW vw_opcao_b3_motivo_validacao AS
SELECT
    status_validacao,
    motivo_rejeicao,
    COUNT(*) AS total_registros
FROM opcao_b3_diaria
WHERE status_validacao <> 'VALIDA'
GROUP BY status_validacao, motivo_rejeicao;
