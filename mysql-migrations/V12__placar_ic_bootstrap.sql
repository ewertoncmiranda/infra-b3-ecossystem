-- Intervalo de confianca por bootstrap em blocos de meses (infra#TASK-31).
--
-- O intervalo da V9 (Wilson / media +- 1,96 erro-padrao) supoe janelas
-- independentes; no backtest nao sao: ativos do mesmo mes andam juntos e
-- meses vizinhos se sobrepoem no horizonte. O gerar-insights reamostra blocos
-- de meses consecutivos (tamanho do horizonte) e grava os percentis 2,5/97,5;
-- o gestor prefere estes quando existem.
--
-- Idempotente (volume novo ja recebe as colunas; reaplicar nao falha).

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'backtest_placar'
             AND COLUMN_NAME = 'ic_acerto_inferior'),
    'SELECT 1',
    'ALTER TABLE backtest_placar
        ADD COLUMN ic_acerto_inferior DECIMAL(8,6) NULL,
        ADD COLUMN ic_acerto_superior DECIMAL(8,6) NULL,
        ADD COLUMN ic_excesso_carteira_inferior DECIMAL(12,6) NULL,
        ADD COLUMN ic_excesso_carteira_superior DECIMAL(12,6) NULL,
        ADD COLUMN meses_bootstrap INT NULL'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
