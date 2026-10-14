-- Idempotência do fluxo SQS de snapshots. As verificações tornam esta
-- migration segura tanto sobre volumes antigos quanto sobre o schema novo.

SET @sql = IF(
    EXISTS(
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'historico_acoes'
          AND COLUMN_NAME = 'dedup_key'
    ),
    'SELECT 1',
    'ALTER TABLE historico_acoes ADD COLUMN dedup_key VARCHAR(64) NULL AFTER id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    EXISTS(
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'historico_acoes'
          AND INDEX_NAME = 'uq_historico_acoes_dedup_key'
    ),
    'SELECT 1',
    'ALTER TABLE historico_acoes ADD UNIQUE KEY uq_historico_acoes_dedup_key (dedup_key)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    EXISTS(
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'insight_acao'
          AND COLUMN_NAME = 'dedup_key'
    ),
    'SELECT 1',
    'ALTER TABLE insight_acao ADD COLUMN dedup_key VARCHAR(64) NULL AFTER id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(
    EXISTS(
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'insight_acao'
          AND INDEX_NAME = 'uq_insight_acao_dedup_key'
    ),
    'SELECT 1',
    'ALTER TABLE insight_acao ADD UNIQUE KEY uq_insight_acao_dedup_key (dedup_key)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
