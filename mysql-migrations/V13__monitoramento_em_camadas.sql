-- Monitoramento em camadas (2026-09-27): a BRAPI fica so para os favoritos.
--
--   REFERENCIA_DIARIA  universo de referencia por setor: preco diario oficial
--                      (COTAHIST), sem nenhuma chamada a BRAPI;
--   COTACAO_E_HISTORICO  favoritos do usuario: cotacao intradiaria da BRAPI a
--                      cada 15 min, so em dia util, no horario do pregao.
--   COTACAO            legado; tratado como REFERENCIA_DIARIA.
--
-- Por que: 30 referencias de hora em hora mais 1 favorito a cada 30 s davam
-- ~35 mil chamadas/mes, contra 15 mil do plano gratuito da BRAPI.
-- Idempotente (reaplicar nao falha; o dado converge).

SET @sql = IF(
    EXISTS(SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ativo_monitorado'
             AND CONSTRAINT_NAME = 'chk_ativo_monitorado_tipo'),
    'ALTER TABLE ativo_monitorado DROP CHECK chk_ativo_monitorado_tipo',
    'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
ALTER TABLE ativo_monitorado ADD CONSTRAINT chk_ativo_monitorado_tipo
    CHECK (tipo_coleta IN ('COTACAO', 'COTACAO_E_HISTORICO', 'REFERENCIA_DIARIA'));

UPDATE ativo_monitorado SET tipo_coleta = 'REFERENCIA_DIARIA' WHERE tipo_coleta = 'COTACAO';
-- Favorito a cada 30 s gastava sozinho mais que a cota inteira (RAIZ4).
UPDATE ativo_monitorado SET intervalo_segundos = 900
 WHERE tipo_coleta = 'COTACAO_E_HISTORICO' AND intervalo_segundos < 900;
