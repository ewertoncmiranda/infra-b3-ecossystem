-- Placar do backtest diz quantas janelas tiveram o retorno ajustado por
-- provento (infra#TASK-36, gerar-insights#TASK-56). O ajuste existe desde
-- gerar-insights 7ea0d1e/13b6287, mas a fonte so cobre de 2026-09-27 em
-- diante: sem esta contagem, a tela nao distingue "sem provento" de "sem dado".
--
-- Idempotente: o mysql-init de volume novo ja cria a coluna.

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'backtest_placar'
             AND COLUMN_NAME = 'janelas_com_provento'),
    'SELECT 1',
    'ALTER TABLE backtest_placar ADD COLUMN janelas_com_provento INT NOT NULL DEFAULT 0 AFTER desvio_excesso_carteira'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
