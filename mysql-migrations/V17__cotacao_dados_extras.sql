-- V17__cotacao_dados_extras.sql
-- TASK-E10: numero_negocios NAO entra aqui - a coluna existe desde a V1
-- (cotacao_b3_diaria); um ADD COLUMN falharia com "Duplicate column" e
-- travaria o db-migrate. Falta so o ETL grava-la (TASK-E10).

-- TASK-E11: ISIN (CODISI, posicoes 231-242 do COTAHIST; Codigo_ISIN do FCA).
-- Permite resolver renomeacoes de ticker de forma canonica e cruzar com bases
-- internacionais sem depender do codigo de negociacao.
ALTER TABLE cvm_ticker
    ADD COLUMN isin VARCHAR(12) NULL AFTER tipo_valor_mobiliario;

ALTER TABLE cotacao_b3_diaria
    ADD COLUMN isin VARCHAR(12) NULL AFTER numero_negocios,
    ADD KEY idx_cotacao_b3_isin (isin, data_pregao);
