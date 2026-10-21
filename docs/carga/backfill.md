# Backfill das fontes novas pela API do ETL

Sem o profile `etl` e sem CLI do ETL: o backfill é um `POST /cargas` feito por `scripts/cargas-etl.ps1 -Backfill` (URL em `ETL_URL_HOST`, padrão `http://127.0.0.1:8097`; token em `ETL_TOKEN`, enviado como `X-ETL-Token`).

## Pré-requisitos

1. Migration **V45** aplicada (a V44 recusa as etapas novas em `carga_etapa`).
2. ETL com a **FONTES-ETL-8** (as etapas novas no catálogo). Sem ela o ETL não conhece as etapas e o script avisa, se `GET /saude` listar as etapas, ou o ETL responde erro.
3. Stack no ar (o ETL é o serviço do compose, porta `127.0.0.1:8097`).

## Uso

```powershell
# carga COMPLETA (todas as etapas, ultimos 5 anos)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cargas-etl.ps1 -Backfill
# PARCIAL por etapa
... -Backfill -Etapas CVM_CADASTRO
... -Backfill -Etapas CVM_FRE -Anos 2022,2023,2024
# ver o corpo que seria enviado, sem rede
... -Backfill -Etapas TESOURO -DryRun
```

Etapas aceitas: as 11 do catálogo (`COTAHIST`, `LIQUIDEZ`, `PRONTIDAO`, `QUALIDADE_OPCOES`, `CONCILIACAO`, `DFP`, `TTM`, `IPE`, `DVA`, `EVENTOS`, `CHECAGENS`) mais `TESOURO`, `IFDATA`, `CVM_CADASTRO`, `CVM_VLMO`, `CVM_FRE`, `CVM_CDA`. Etapa desconhecida aborta antes de chamar o ETL.

## Ordem recomendada e volume

Uma etapa por vez (só uma carga roda por vez; segunda chamada recebe 409):

| # | Etapa | Download |
|---|---|---|
| 1 | `CVM_CADASTRO` | cadastro de companhias (arquivo único, pequeno) |
| 2 | `TESOURO` | 14,6 MB, único |
| 3 | `IFDATA` | OData do BCB, consulta por período |
| 4 | `CVM_FRE` | 8,5 MB por ano |
| 5 | `CVM_VLMO` | 0,8 MB por ano |
| 6 | `CVM_CDA` | 13 MB por mês (24 meses, só ações) |

Os arquivos ficam em cache (ETag), então repetir custa uma requisição HEAD quando não há novidade.

## Acompanhar

O script imprime cada etapa que muda de status e, no fim, status, alertas e erros por etapa (limite `B3_CARGA_TIMEOUT_MIN`, padrão 240 min; a carga continua no ETL se o limite estourar). Log: `%USERPROFILE%\b3-ecossistema\cargas-etl.log`. Também dá para ver `GET /cargas/{id}` e a tela Cargas de dados do painel. Carga já em andamento (409): o script informa o id e sai sem erro.

## Repetir uma etapa

Use `-Forcar` para reprocessar mesmo com ETag já registrado, com os anos desejados:

```powershell
... -Backfill -Etapas CVM_FRE -Anos 2023 -Forcar
```
