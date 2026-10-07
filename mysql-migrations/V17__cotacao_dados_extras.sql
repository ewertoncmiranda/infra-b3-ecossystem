-- V17__cotacao_dados_extras.sql
-- TASK-E10: numero de negocios por pregao (TOTNEG, posicoes 148-152 do COTAHIST).
-- O LeitorCotahist e o CandleB3 ja carregavam o campo; faltava so a coluna.
ALTER TABLE cotacao_b3_diaria
    ADD COLUMN numero_negocios INT NULL AFTER volume_financeiro;

-- TASK-E11: ISIN (CODISI, posicoes 231-242 do COTAHIST; Codigo_ISIN do FCA).
-- Permite resolver renomeacoes de ticker de forma canonica e cruzar com bases
-- internacionais sem depender do codigo de negociacao.
ALTER TABLE cvm_ticker
    ADD COLUMN isin VARCHAR(12) NULL AFTER tipo_valor_mobiliario;

ALTER TABLE cotacao_b3_diaria
    ADD COLUMN isin VARCHAR(12) NULL AFTER numero_negocios,
    ADD KEY idx_cotacao_b3_isin (isin, data_pregao);
