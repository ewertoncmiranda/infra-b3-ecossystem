-- TASK-32 (sinais tecnicos como regras proprias no backtest): as versoes das regras tecnicas
-- (`TECNICO_MOMENTUM_2026.10.07-1`, `TECNICO_REVERSAO_2026.10.07-1`, ate 29 caracteres) nao cabiam
-- em versao_regra VARCHAR(20) do placar; a primeira execucao real do backtest falhava no INSERT
-- (erro 1406). Alarga as duas tabelas do backtest para 40, acima das versoes operacionais (30).
-- So aumenta o tamanho: nenhum dado existente muda.

ALTER TABLE backtest_placar MODIFY versao_regra VARCHAR(40) NOT NULL;
ALTER TABLE backtest_ranking_mes MODIFY versao_regra VARCHAR(40) NOT NULL;
