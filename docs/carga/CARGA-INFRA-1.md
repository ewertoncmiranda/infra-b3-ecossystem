# CARGA-INFRA-1 — IMPLEMENTADO (2026-10-18)

Entregue: `mysql-migrations/V44__controle_de_cargas.sql` — `carga_execucao`, `carga_etapa` (FK com cascade, UK execução+etapa), coluna `etl_execucao.carga_execucao_id` (FK `SET NULL`) e `vw_carga_ultima`. Collation `utf8mb4_0900_ai_ci`, igual às tabelas existentes. Aditiva: não altera nem apaga dados.

Evidência:
- Banco novo (MySQL 8.0 temporário + `flyway/flyway:10.17.0` do compose): 40 migrations da develop + V44 aplicadas, schema v44.
- Upgrade do banco local: `db-migrate` validou 44 migrations e aplicou a V44 (v43 → v44).
- No banco temporário: `vw_carga_ultima` devolve a última tentativa (FALHA de 18/10) e o último sucesso (17/10) do COTAHIST; etapa `PULADA` não conta; `ALERTA` conta como tentativa, não como sucesso; apagar a carga deixa `etl_execucao.carga_execucao_id` nulo e remove as etapas; os 5 CHECKs recusam tipo, solicitante, status e etapa fora do catálogo.

Desvio: catálogo ganhou a etapa `CONCILIACAO` (brapi × COTAHIST), que a rotina da manhã já executava e faltava no plano.
