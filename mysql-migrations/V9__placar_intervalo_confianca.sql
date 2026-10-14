-- Intervalo de confianca no placar do backtest (TASK-30).
--
-- A media do excesso sozinha nao diz se a diferenca e sinal ou ruido: com
-- 24 janelas, "+3,6% sobre a carteira" pode ir de negativo a +8%. Com o
-- desvio-padrao e a quantidade de janelas que TEM excesso (a media da carteira
-- fica nula com menos de 5 ativos), o gestor calcula media +- 1,96 erro-padrao.
-- O acerto usa o intervalo de Wilson, que so precisa de acertos e avaliados.
--
-- Idempotente: o mysql-init de volume novo ja cria as colunas.

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'backtest_placar'
             AND COLUMN_NAME = 'desvio_excesso_carteira'),
    'SELECT 1',
    'ALTER TABLE backtest_placar
        ADD COLUMN n_excesso_cdi INT NULL AFTER excesso_medio_carteira,
        ADD COLUMN desvio_excesso_cdi DECIMAL(12,6) NULL AFTER n_excesso_cdi,
        ADD COLUMN n_excesso_carteira INT NULL AFTER desvio_excesso_cdi,
        ADD COLUMN desvio_excesso_carteira DECIMAL(12,6) NULL AFTER n_excesso_carteira'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
