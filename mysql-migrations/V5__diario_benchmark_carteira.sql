-- Diario de sinais: o benchmark de mercado deixa de ser o BOVA11 (que o
-- ecossistema nao coleta) e passa a ser a MEDIA SIMPLES DA CARTEIRA
-- monitorada no mesmo periodo - "a regra escolheu melhor do que pegar todos
-- os ativos por igual?". Contrato: CTR-11.
--
-- Idempotente (mesmo estilo da V2): volume novo recebe as colunas ja com o
-- nome novo pelo mysql-init, e o Flyway reaplica esta migration por cima.
-- Feita antes do primeiro sinal gravado, entao nao ha dado a migrar.

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sinal_resultado'
             AND COLUMN_NAME = 'retorno_bova11'),
    'ALTER TABLE sinal_resultado RENAME COLUMN retorno_bova11 TO retorno_carteira',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sinal_resultado'
             AND COLUMN_NAME = 'excesso_bova11'),
    'ALTER TABLE sinal_resultado RENAME COLUMN excesso_bova11 TO excesso_carteira',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Contra quantos ativos a media foi calculada: com poucos ativos no periodo
-- o "excesso sobre a carteira" diz pouco, e a tela precisa mostrar isso.
SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sinal_resultado'
             AND COLUMN_NAME = 'ativos_na_carteira'),
    'SELECT 1',
    'ALTER TABLE sinal_resultado ADD COLUMN ativos_na_carteira SMALLINT NULL AFTER excesso_carteira'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
