# Plano: atualização diária dos dados (máquina só em horário comercial)

Autor: Sessão 03, 2026-09-28. Dividido em 3 frentes, uma por sessão e por repositório,
para ninguém editar o mesmo arquivo.

| Frente | Sessão | Repositório(s) |
|---|---|---|
| A. Infra e orquestração | **Sessão 02** | `infra-b3-ecossytem` |
| B. Coleta BRAPI e orçamento de cota | **Sessão 01** | `gestor-ativos-brutos` |
| C. Insights, recuperação e conciliação | **Sessão 03** | `gerar-insights`, `etl-fundamentos-cvm` |

## 1. Contexto (fatos medidos em 2026-09-28)

- A máquina fica ligada só em horário comercial. Hoje as tarefas de 20:00 e 21:30 dependem
  dela ligada à noite, e `StartWhenAvailable=False`: dia com a máquina desligada é carga perdida.
- Depois de um boot, `mysql`, `localstack`, `elasticsearch`, `logstash`, `kibana`, `prometheus` e
  `grafana` ficam parados (não têm `restart:`). O LocalStack roda sem persistência: as filas somem
  e só o `docker compose up` (provisionador) as recria. Foi assim que 83 mensagens se perderam.
- O provisionador usa a imagem do Docker Hub `ewertonmiranda/infra-b3-ecossystem:latest` (de 21/06),
  não o `./infra` local. Por isso não existem DLQs, `sqs-comunicados-publicados` nem o SNS
  (o módulo local já cria DLQ via `redrive_policy`).
- B3: o COTAHIST do pregão D sai por volta das 21:50 de D. CVM: IPE às 07:00, DFP às 07:15,
  ITR às 07:44 (horário de Brasília).
- O backtest entra na **abertura do pregão seguinte** (`avaliador.py`, `indice_sinal + 1`). Gerar
  o sinal na manhã de D+1, antes das 10:00, é exatamente essa premissa.
- `insights_diarios` sem `--data` analisa só o último pregão: dia perdido vira buraco em
  `insight_acao` e `sinal_diario`.
- BRAPI no plano gratuito: 15.000 req/mês, **1 ativo por requisição**, dados atualizados a cada
  **30 min**, histórico de até 3 meses. Consumo hoje: cerca de 100 req/dia útil, com desperdício
  (histórico a cada 5 min e cotação a cada 15 min para um dado que muda a cada 30).
- Comparei 970 pares brapi × COTAHIST já existentes: OHLC e volume 100% idênticos. Só o
  `adjusted_close` difere (43 casos). **Na conciliação, comparar sempre o `close` bruto.**

## 2. Decisões

- **D1 Ciclo diário na manhã de D+1.** Disparos: ao fazer logon (+5 min) e às 07:00 em dias úteis,
  com `StartWhenAvailable=True`. Segunda passada às 12:30, junto com o backup. Ficam aposentadas
  as tarefas de 20:00 e 21:30.
- **D2 Insights e sinais só com o COTAHIST oficial.** Nada de insight preliminar com a brapi.
- **D3 BRAPI só para o intradiário dos favoritos** (`tipo_coleta = COTACAO_E_HISTORICO`): a cada
  30 min, 10:05 a 17:35, em dias de pregão. Só o endpoint de cotação, e o candle do dia derivado
  dele. Sem histórico a cada 5 min e sem varredura de fechamento.
  - Orçamento: 13.500/mês, com 10% de reserva.
  - Máximo de favoritos: (13.500 − 390) ÷ (16 × 23) ≈ **35**.
- **D4 Conciliação brapi × COTAHIST com custo zero.** Às 17:40, copiar a última cotação dos
  favoritos (a do ciclo das 17:35) para uma tabela imutável. Na manhã seguinte, comparar com o
  COTAHIST.
- **D5 Uma única sessão cria migrações Flyway: a Sessão 02.** A próxima é a **V15** (DDL na
  seção 4). As outras frentes codificam contra esse contrato.

## 3. Ciclo-alvo

| Quando (BRT) | Quem | O quê |
|---|---|---|
| Logon +5 min / 07:00 | A (script) | Garantir a stack → IPE, DFP, TTM, COTAHIST (ETL) → conciliação (C) → insights `--recuperar` (C) → diário com recuperação (C) → backtest (sextas) |
| 10:05–17:35, a cada 30 min | B (gestor) | Cotação dos favoritos pela brapi → `cotacao_atual` + `candle_diario` do dia |
| 12:30 | A (script) | Backup + segunda passada do ETL (só consultas HEAD quando não há novidade) |
| 17:40 | B (gestor) | Foto imutável dos favoritos em `snapshot_fechamento_brapi` |
| 08:30, dias úteis | B (gestor) | Índices macro, IBGE, proventos e perfil (cron fixo, não mais `fixedDelay`) |

## 4. Contratos entre frentes (não mudar sem avisar as outras sessões)

### 4.1 Migração V15 (Sessão 02 cria; as Frentes B e C usam)

```sql
CREATE TABLE brapi_consumo (
  dia DATE NOT NULL,
  endpoint VARCHAR(40) NOT NULL,          -- quote | quote-lote | historical | profile
  quantidade INT NOT NULL DEFAULT 0,
  atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (dia, endpoint)
);

CREATE TABLE snapshot_fechamento_brapi (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  simbolo VARCHAR(12) NOT NULL,
  data_pregao DATE NOT NULL,
  abertura DECIMAL(14,4), maxima DECIMAL(14,4), minima DECIMAL(14,4),
  fechamento DECIMAL(14,4),               -- close BRUTO, nunca o ajustado
  volume BIGINT,
  horario_dado_brapi DATETIME NULL,       -- regularMarketTime da cotação
  capturado_em DATETIME NOT NULL,
  status_captura VARCHAR(20) NOT NULL,    -- OK | ERRO_HTTP | SEM_DADO
  UNIQUE KEY uq_snapshot_fechamento_brapi (simbolo, data_pregao)
);

CREATE VIEW vw_conciliacao_preco AS
SELECT s.simbolo, s.data_pregao,
       s.fechamento AS fech_brapi, b.fechamento AS fech_b3,
       b.fechamento - s.fechamento                                   AS dif_fechamento,
       ROUND((b.fechamento - s.fechamento) / 0.01)                   AS dif_fechamento_ticks,
       ROUND((b.fechamento - s.fechamento) / b.fechamento * 100, 4)  AS dif_fechamento_pct,
       b.abertura - s.abertura AS dif_abertura,
       b.maxima - s.maxima     AS dif_maxima,
       b.minima - s.minima     AS dif_minima,
       b.volume - s.volume     AS dif_volume,
       ROUND((b.volume - s.volume) / NULLIF(b.volume, 0) * 100, 2)   AS dif_volume_pct,
       TIMESTAMPDIFF(MINUTE, s.horario_dado_brapi, s.capturado_em)   AS idade_dado_min,
       CASE
         WHEN s.status_captura <> 'OK'                                  THEN 'SEM_BRAPI'
         WHEN b.simbolo IS NULL AND CURRENT_DATE > s.data_pregao        THEN 'SEM_B3'
         WHEN b.simbolo IS NULL                                         THEN 'PENDENTE'
         WHEN ABS(b.fechamento - s.fechamento) >= 0.01
           OR ABS(b.maxima - s.maxima) >= 0.01
           OR ABS(b.minima - s.minima) >= 0.01                          THEN 'DIVERGENTE_PRECO'
         WHEN ABS(b.volume - s.volume) / NULLIF(b.volume, 0) > 0.01     THEN 'DIVERGENTE_VOLUME'
         ELSE 'OK'
       END AS divergencia,
       CASE
         WHEN b.simbolo IS NULL OR s.status_captura <> 'OK'                 THEN NULL
         -- GRAVE exige 2+ ticks E > 0,5%: 1 centavo numa acao de R$ 0,29 e 3,4%
         -- e nao pode disparar alerta sozinho (validado em banco temporario).
         WHEN ABS(b.fechamento - s.fechamento) >= 0.02
          AND ABS(b.fechamento - s.fechamento) / b.fechamento > 0.005       THEN 'GRAVE'
         WHEN ABS(b.fechamento - s.fechamento) >= 0.01                      THEN 'LEVE'
       END AS severidade
FROM snapshot_fechamento_brapi s
LEFT JOIN cotacao_b3_diaria b
       ON b.simbolo = s.simbolo AND b.data_pregao = s.data_pregao;
```

### 4.2 Linhas registradas em `etl_execucao` (`fonte`)
- `CONCILIACAO_BRAPI_B3` (C): `competencia` = data do pregão, `linhas_carregadas` = quantidade
  divergente, `status` = SUCESSO | ERRO (ERRO quando há GRAVE ou mais de 2% de DIVERGENTE_PRECO),
  resumo em `mensagem_erro`.
- `BRAPI_ORCAMENTO` (B): `competencia` = AAAA-MM, `status` = ERRO quando a cota estourar ou
  vier 429.

### 4.3 Comandos que o script da Frente A chama (a Frente C entrega)
- `docker compose ... run --rm --no-deps gerar-insights python -m app.insights_diarios --recuperar`:
  gera os insights de todo pregão do COTAHIST posterior ao último insight (limite de 30 pregões).
  Idempotente. Código de saída 0 quando não há nada a fazer.
- `docker compose ... run --rm --no-deps gerar-insights python -m app.validacao.diario registrar`
  (**sem `--data`**): já recupera todo pregão do COTAHIST ainda sem sinal. Já existe, não há flag nova.
  Depois: `... python -m app.validacao.diario avaliar`.
- `docker compose ... --profile etl run --rm --no-deps etl-fundamentos-cvm --conciliar [--data AAAA-MM-DD]`:
  sem `--data`, concilia todos os pregões com `divergencia = 'PENDENTE'` resolvidos desde a última
  conciliação. Sai com 0, ou com 3 quando há alerta (divergência grave). Antes da V15 existir,
  registra aviso e sai com 0.

## 5. Frente A: Sessão 02 (`infra-b3-ecossytem`)

- **A1** Adicionar `restart: unless-stopped` a `mysql`, `localstack`, `elasticsearch`, `logstash`,
  `kibana`, `prometheus` e `grafana`.
- **A2** Pôr o `etl-fundamentos-cvm` em `profiles: ["etl"]` (o comentário já diz isso, mas a chave
  não existe) e remover o `command: ["--rotina"]`. Assim o `up` não dispara carga, e o único
  orquestrador passa a ser o script.
- **A3** Criar `Garantir-Stack` em `comum.ps1`:
  1. Esperar o Docker Engine responder (limite de 5 min).
  2. Rodar `docker compose -f docker-compose-local.yml up -d`.
  3. Esperar `mysql` saudável, `db-migrate` e `my-terraform-provisioner` com código 0.
  4. Se falhar, registrar ERRO em `etl_execucao` e mandar alerta.
- **A4** Reescrever `cargas-etl.ps1` como "rotina da manhã", nesta ordem: `Garantir-Stack` →
  IPE, DFP, TTM, COTAHIST → `--conciliar` → insights `--recuperar` → diário `registrar` (sem `--data`) e `avaliar` →
  backtest (sextas). Incorporar o `diario-de-sinais.ps1`.
- **A5** Reescrever as tarefas em `registrar-rotinas.ps1`:
  - "B3 - Rotina da manha": gatilho AtLogOn com atraso de 5 min + semanal 07:00 (seg a sex).
    Configurar `StartWhenAvailable=True`, `DisallowStartIfOnBatteries=False`,
    `StopIfGoingOnBatteries=False`, `MultipleInstances=IgnoreNew`.
  - "B3 - Backup MySQL" às 12:30, seguido de uma segunda passada do ETL.
  - Remover "B3 - Cargas ETL" (20:00) e "B3 - Diario de sinais" (21:30).
- **A6** Criar a migração **V15** exatamente como na seção 4.1.
- **A7** Fazer o provisionador usar o `./infra` local (`build: ./infra`) em vez da imagem do
  Docker Hub. Com isso passam a existir as DLQs, `sqs-comunicados-publicados` e o SNS.
- **A8** (opcional) No `logstash.conf`, trocar o `codec => json` do input de arquivo por `plain`.
  Hoje 100% dos documentos recebem `_jsonparsefailure`.
- **Aceite:**
  - Simular um boot com `docker compose down`, depois rodar a tarefa: a stack fica saudável e a
    rotina termina com as linhas esperadas em `etl_execucao`.
  - `flyway info` mostra a V15.
  - As filas têm `RedrivePolicy`.
  - **Avisar as Sessões 01 e 03 antes de derrubar a stack.**

## 6. Frente B: Sessão 01 (`gestor-ativos-brutos`)

- **B1** Trocar os `@Scheduled(fixedDelay = 86_400_000)` (índices macro, IBGE, proventos) e o de
  perfil de empresa por `@Scheduled(cron = "0 30 8 * * MON-FRI", zone = "America/Sao_Paulo")`.
  Não rodar na inicialização.
- **B2** Cotação intradiária com `cron = "0 5,35 10-17 * * MON-FRI"` e zona de São Paulo:
  - Só os favoritos (`COTACAO_E_HISTORICO`) e só com `seletorDeColeta.pregaoAberto()`.
  - Último ciclo às 17:35.
  - Substitui o laço de 5 s com `intervaloSegundos`.
- **B3** Derivar o candle do dia (`candle_diario`) da própria cotação (open/dayHigh/dayLow/price/
  volume) e **remover** o laço de histórico a cada 5 min. O histórico (`range=3mo`) fica só para
  o preenchimento inicial, uma vez, quando um ativo vira favorito.
- **B4** Contador `brapi_consumo`: incrementar em `ClienteBrApi.executarGet` por dia e endpoint.
  Serviço de orçamento:
  - `brapi.orcamento.mensal=13500`.
  - Antes de cada ciclo, projetar o consumo até o fim do mês.
  - Se não couber, passar de 30 para 60 min e depois desligar o intradiário.
  - Com 429 ou cota esgotada, interromper o ciclo e registrar `BRAPI_ORCAMENTO` = ERRO.
- **B5** Foto das 17:40 (`cron = "0 40 17 * * MON-FRI"`): para cada favorito com cotação do dia,
  fazer `INSERT IGNORE` em `snapshot_fechamento_brapi` a partir de `cotacao_atual` e do candle do
  dia, com `horario_dado_brapi = regular_market_time`. **Nenhuma chamada à brapi.**
- **B6** Limitar favoritos ativos a `brapi.favoritos.max=35`: o POST `/favoritos/{simbolo}` recusa
  acima disso, com mensagem clara.
- **B7** Correções vistas na análise:
  - Rota inexistente devolve 500 (`NoResourceFoundException` no `TratadorGlobalExcecoes`); o certo é 404.
  - A RAIZ4 está com `versao` 1826 em `ativo_monitorado`, contra 54 da PRIO3, com o mesmo intervalo.
    Investigar a regravação excessiva.
  - `/validacao/saude-dados` diz que `INSIGHTS_BASE` está OK mesmo com o consumidor parado. Deve olhar o
    atraso de `MAX(insight_acao.data_analise)` em relação ao último pregão do COTAHIST.
- **Aceite:**
  - Testes passando.
  - Num dia de pregão, o consumo em `brapi_consumo` fica ≤ favoritos × 16 + perfis.
  - Nenhuma chamada à brapi fora de 10:05–17:35 além do cron das 08:30.
  - A foto das 17:40 gravada.

## 7. Frente C: Sessão 03 (`gerar-insights`, `etl-fundamentos-cvm`)

- **C1** `insights_diarios --recuperar`, conforme a seção 4.3.
- **C2** ~~`diario registrar --recuperar`~~: não é necessário. `registrar` sem `--data` já recupera
  (`pregoes_a_registrar`).
- **C3** ETL `--conciliar`: lê `vw_conciliacao_preco`, registra `CONCILIACAO_BRAPI_B3` e define o
  código de saída, conforme a seção 4.2.
- **C4** Testes e checagens (pytest, ruff, mypy) nos dois repositórios.
- **Aceite:** com um pregão faltando em `insight_acao`, o `--recuperar` preenche o buraco. Rodar de
  novo não grava nada.

## 8. Ordem e dependências

1. A6 (V15) primeiro. B4, B5 e C3 podem ser codificados em paralelo contra a seção 4.1.
2. A4 depende das flags da seção 4.3. Os nomes estão fixados aqui; enquanto a Frente C não
   entrega, o script pode chamar os comandos antigos.
3. O teste de boot (aceite da Frente A) roda por último, com aviso às outras sessões.

## 9. Regras para as três sessões

- Trabalhar em branch `feature-*` de cada repositório, **nunca** em `main`. PR abre sozinho.
- **Só commitar e dar push quando o usuário pedir.** Adicionar arquivos um por um, nunca `git add .`.
- Não mexer em arquivos de outra frente. Precisou? Mande mensagem para a sessão dona.
- Antes de derrubar ou recriar contêineres compartilhados, avisar as outras sessões.
- Ao terminar, mandar para a Sessão 03 o que foi feito, os testes e as pendências.
