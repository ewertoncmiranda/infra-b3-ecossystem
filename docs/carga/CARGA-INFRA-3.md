# CARGA-INFRA-3 — IMPLEMENTADO (2026-10-18)

Entregue em `scripts/cargas-etl.ps1`: as seis chamadas ao ETL por `docker compose run` saem; entra `Rodar-Carga`, que faz `POST /cargas` (`tipo=ROTINA`, `solicitada_por=ROTINA_MANHA`), acompanha `GET /cargas/{id}` a cada 15 s (limite `B3_CARGA_TIMEOUT_MIN`, padrão 240 min) e registra no log cada etapa que muda de status, os alertas e os erros. Eventos corporativos mensais viram `PARCIAL` com `etapas: ["EVENTOS"]`; os fatores continuam como passo de insights, depois. As cargas do ETL rodam antes dos insights, como antes.

Regras: `FALHA`, `SUCESSO_PARCIAL`, `INTERROMPIDA`, tempo esgotado ou ETL fora do ar entram nas falhas da rotina (alerta do Telegram); `SUCESSO_COM_ALERTA` só registra aviso; 409 espera a carga em andamento e pede de novo uma vez. Token em `X-ETL-Token` quando `ETL_TOKEN` existe no ambiente do usuário.

Evidência: funções extraídas do script e executadas contra um ETL simulado — 409 + sucesso com alerta (código 0, aviso no log), falha parcial (código 1, erro no log), ETL fora do ar (código 1). Script sem erros de sintaxe.

Achado: a rotina atual já estava quebrada na parte do ETL — chamava `--comunicados`, `--ttm`, `--cotahist`, `--conciliar`, `--eventos-corporativos` e `--universo-backtest`, que o `main.py` não aceita mais.

Pendente (CARGA-INFRA-4): `scripts/backfill-historico.ps1` ainda usa `--profile etl run` e vai quebrar com o entrypoint novo.
