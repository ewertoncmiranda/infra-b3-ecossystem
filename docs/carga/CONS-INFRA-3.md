# CONS-INFRA-3 — IMPLEMENTADO (2026-10-20)

## Entregue
- `scripts/cargas-etl.ps1`: modo `-Backfill` (parâmetros `-Etapas`, `-Anos`, `-Simbolos`, `-Forcar`, `-DryRun`) e função `Rodar-Backfill`. Sem etapas dispara `COMPLETA`; com etapas, `PARCIAL`. `solicitada_por=API`. Acompanha `GET /cargas/{id}` reusando `Aguardar-Carga` e imprime o status por etapa, alertas e erros. URL e token pelas mesmas variáveis da rotina (`ETL_URL_HOST`, `ETL_TOKEN`). Sem `-Backfill`, a rotina da manhã segue igual.
- Validação das etapas contra o catálogo (11 atuais + TESOURO, IFDATA, CVM_CADASTRO, CVM_VLMO, CVM_FRE, CVM_CDA) e, se `GET /saude` listar `etapas`, contra o ETL. Etapa desconhecida = erro claro, sem `POST`. 409 = mensagem com o id em andamento e saída 0.
- `docs/carga/backfill.md`: guia (pré-requisitos, ordem, volumes, acompanhamento, `-Forcar`).
- Pré-requisito explícito: V45 aplicada e ETL com FONTES-ETL-8. A V45 não foi alterada.

## Evidência
- Parser do PowerShell: 0 erros de sintaxe.
- `-Backfill -DryRun` sem rede e sem subir a stack: sem etapas gera `{"tipo":"COMPLETA","solicitada_por":"API"}`; `-Etapas CVM_FRE -Anos 2024,2025 -Forcar` gera `{"tipo":"PARCIAL","etapas":["CVM_FRE"],"anos":[2024,2025],"forcar":true,"solicitada_por":"API"}`; `XPTO` e ano inválido saem com código 1 sem chamar o ETL.
- Nenhum backfill real executado e nenhum container tocado (o ETL ainda não conhece as etapas novas).

## Desvios
- `-DryRun` em vez de `-WhatIf`, e ele pula a verificação de `/saude` (offline).
- Não foi tocado `scripts/backfill-historico.ps1` (fora dos arquivos permitidos); ele ainda usa `--profile etl run` e fica obsoleto, a remover/redirecionar em tarefa própria. `PROXIMOS-PASSOS.md` e `PLANO-ATUALIZACAO-DIARIA.md` também não foram alterados.
- O formato de `etapas` em `GET /saude` não está no contrato; a checagem só vale se o endpoint trouxer a lista.
- Não testados contra ETL real: o acompanhamento e o 409 reusam `Chamar-Etl`/`Aguardar-Carga` já validados na CARGA-INFRA-3.
