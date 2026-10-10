# Contratos operacionais (OPR-INFRA-2)

Eventos do plano OPR (sistema em **modo simulado**, paper trading). Fonte única: estes arquivos;
`scripts/sincronizar-contratos.mjs` copia os schemas para o `gerar-insights` (produtor) e gera o enum
`StatusOperacional` em Python, Java e JS. Teste: `npm ci && npm test` na raiz da infra (também na esteira).

| Contrato | `evento_operacional.tipo` (V23) | Produtor | Consumidores |
|---|---|---|---|
| `operacional.sinal-gerado.v1` | `SINAL_GERADO` | gerar-insights | gestor, painel, alertas |
| `operacional.posicao-aberta.v1` | `POSICAO_ABERTA` | gerar-insights | gestor, painel, Telegram (via adapter) |
| `operacional.posicao-fechada.v1` | `POSICAO_FECHADA` | gerar-insights | gestor, painel, Telegram (via adapter) |
| `operacional.diario-avaliado.v1` | `DIARIO_AVALIADO` | gerar-insights | gestor, painel |
| `operacional.alerta-risco.v1` | `ALERTA_RISCO` | gerar-insights / gestor | Telegram (via adapter) |

Regras comuns (`comum.v1.schema.json#/$defs/envelope`):

- Envelope: `schemaVersion` (`"1"`), `eventId` (UUID, idempotência), `correlationId`, `evento` (nome do
  contrato), `versao_regra` (`OPR-AAAA.MM.DD-N`), `dataPregao`, `emitidoEm`, `modo` (sempre `SIMULADO`),
  `aviso` e `dados`. Campo fora do contrato é recusado, no envelope e em `dados`.
- Campos de `dados` em snake_case, com os nomes das colunas da V23. Valores em R$; frações (`0.0052` = 0,52%);
  `drawdown` é queda, sempre ≤ 0. Ausente é `null`, nunca 0.
- `status-sistema.v1`: `NAO_OPERAVEL`, `EM_OBSERVACAO`, `PAPER_TRADING_ELEGIVEL`, `BLOQUEADO` — igual ao
  CHECK `ck_diario_status` da V23 (o teste confere). `PAPER_TRADING_ELEGIVEL` nunca autoriza capital real.
- Versão nova de um contrato = arquivo `*.v2.schema.json` novo; o v1 continua aceito até os consumidores migrarem.
- Exemplos em `exemplos/validos` (todo contrato tem pelo menos um) e `exemplos/invalidos` (cada um com o `motivo`).
