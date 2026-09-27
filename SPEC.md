# SPEC — Ecossistema B3 Monitoring (Infraestrutura, Docker e Integração)

| Campo | Valor |
|---|---|
| Versão da spec | 1.0.0 |
| Data | 2026-09-25 |
| Status | Ativa — baseline do estado atual + backlog planejado |
| Branch analisada | `feature-nova-infra` (último commit `81e3fa9`) |
| Alterações não commitadas | `docker-compose.yml`, `infra/*.tf`, `infra/sns/` (novo), `docker-compose-local.yml` (novo, **contém segredos**), `OBSERVABILITY_GUIDE.md` |
| Escopo | Este repositório **e** a integração entre `gestor-ativos-brutos` (Java) e `gerar-insights` (Python) |
| Specs dos serviços | `gestor-ativos-brutos/SPEC.md` · `gerar-insights/SPEC.md` |
| Público | Desenvolvedores humanos e agentes de IA (Codex, ChatGPT, Claude ou outros) |

---

## 1. Como usar este arquivo (protocolo para agentes)

Esta é a **spec de nível de sistema**. Ela é dona de:
- **contratos entre serviços** (`CTR-`): filas, payloads, tabelas compartilhadas, bucket;
- **topologia Docker/Terraform** (`REQ-`, `NFR-`, `ISS-` deste repositório);
- **problemas de integração** (`INT-`), que afetam mais de um repositório.

Regras:
1. Fluxo SDD: `Spec → Plano → Tarefas → Implementação → Verificação → Atualizar Spec`.
2. Uma mudança de contrato (`CTR-`) só pode ser implementada depois que esta spec estiver atualizada, e precisa de uma tarefa correspondente **em cada** repositório afetado.
3. Para referenciar IDs de outras specs, use o prefixo do repositório: `gerar-insights#ISS-01`, `gestor#ISS-02`, `infra#ISS-03`.
4. IDs são estáveis; para descontinuar, use o status `DESCARTADO` com justificativa. Decisões viram `DEC-`.
5. Nunca coloque segredos em arquivos de compose, tfvars ou properties versionados.
6. **Trabalho em paralelo (várias sessões/agentes ao mesmo tempo — `TASK-43`).** Em 2026-09-27 duas sessões editaram os mesmos arquivos e uma commitou o trabalho em andamento da outra. Para não repetir:
   - **Um dono por área de cada vez.** Antes de editar, rode `git status` no repositório: alteração não commitada que não é sua é de outra sessão — não edite esses arquivos nem os inclua em commit. Na dúvida, pergunte.
   - **Commit só do que você alterou:** `git add <arquivos>` explícito; nunca `git add -A`, `git add .` nem `git commit -a`.
   - **Duas sessões no mesmo repositório → worktree próprio**, cada uma na sua branch `feature-*`: `git worktree add ../<repo>-<tarefa> -b feature-<tarefa>`; o merge junta depois.
   - **Avise ao começar e ao terminar** uma área (lista de arquivos) e antes de mexer no que é compartilhado: banco local (migrations, cargas, backtest), containers (`up --build`) e o Agendador.
   - **Banco e containers são compartilhados:** resultado gravado por código em estado intermediário (ex.: um backtest rodado no meio da edição de outra sessão) não vale — descarte e rode de novo.
   - **O SPEC é a fila:** pegue a tarefa marcando `EM ANDAMENTO (sessão/branch)` antes de codar; quem encontrar a marca não começa a mesma tarefa.

---

> Continuando o trabalho? Leia [`PROXIMOS-PASSOS.md`](PROXIMOS-PASSOS.md) primeiro: ele tem o estado atual, a proxima tarefa detalhada e as decisoes que nao devem ser desfeitas sem discussao.

## 2. Visão do sistema

Plataforma de acompanhamento de ações da B3 que coleta cotações, calcula valuation por regras (Graham) e produz uma análise textual com IA.

```
                       ┌────────────────────── Docker network "observability" ───────────────────────┐
  BRAPI (HTTPS) <──────┤ gestor-ativos-brutos (Java, :8091)                                            │
  Gemini (HTTPS) <─────┤   │ publica                      ▲ lê insight_acao          │ grava análise    │
                       │   v                              │                          v                  │
                       │ LocalStack (:4566)  SQS ─────────┼──> gerar-insights (Python worker)  S3 bucket │
                       │   ├ tratar-ativos ───────────────┤      │ grava                                 │
                       │   ├ sqs-registrar-series-historicas     v                                       │
                       │   ├ sqs-iniciar-treinamento (sem uso)  MySQL 8 (:3305 host / :3306 rede)       │
                       │   └ SNS transmitir-lote-dados (sem uso)  historico_acoes, insight_acao,        │
                       │                                          serie_historica                       │
                       │ etl-fundamentos-cvm (job em lote, profile "etl")                              │
                       │   CVM (HTTPS) ──> DFP/ITR/FCA/FRE ──> fato_contabil, indicador_fundamentalista │
                       │ terraform-provisioner (one-shot) ──> cria SQS/S3/SNS no LocalStack              │
                       │ Observabilidade: Prometheus :9090 · Grafana :3000 · ELK (ES :9200, Logstash     │
                       │                  :5000, Kibana :5601)                                          │
                       └─────────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Fluxo ponta a ponta atual
1. Um cliente chama `gestor` (`GET /ativos/{x}`, `GET /ativos/robusto/{x}` ou `POST /ativos/registrar/{x}`).
2. `gestor` consulta a BRAPI e publica a cotação em `tratar-ativos` (e, no modo robusto, a série de 1 ano em `sqs-registrar-series-historicas`).
3. `gerar-insights` consome, grava `historico_acoes`, calcula o insight e grava `insight_acao`; as séries viram *upsert* em `serie_historica`.
4. Nos modos `processar`/robusto, o `gestor` lê `insight_acao` **logo em seguida** (antes do passo 3 terminar, ver `INT-02`), consolida, chama o Gemini e grava o JSON no S3.

---

## 3. Topologia Docker

### 3.1 `docker-compose.yml` (imagens publicadas)

| Serviço | Imagem | Portas host | Depende de | Observações |
|---|---|---|---|---|
| localstack | `localstack/localstack:3.3` | 4566 | — | `SERVICES=sqs,s3,sns`, `DEBUG=1`, volume sem `PERSISTENCE` (estado efêmero) |
| my-terraform-provisioner | `ewertonmiranda/infra-b3-ecossystem:latest` | — | localstack healthy | `entrypoint` sobrescrito para `terraform init && apply` (ignora o `entrypoint.sh`, ver `ISS-06`) |
| mysql | `mysql:8.0` | 3305→3306 | — | `mysql-init/` executado **só na primeira criação do volume** (`ISS-03`) |
| gestor-ativos-brutos | `ewertonmiranda/gestor-ativos-brutos:latest` | 8091 | mysql, localstack, provisioner | `SPRING_PROFILES_ACTIVE=dev`, chaves via `${BRAPI_API_KEY}`/`${GEMINI_API_KEY}` |
| gerar-insights | `ewertonmiranda/gerar-insights:latest` | 8080 | mysql, localstack, provisioner | Porta 8080 exposta, mas **não há servidor HTTP** (`ISS-08`) |
| elasticsearch | `elasticsearch:8.14.0` | 9200 | — | `xpack.security.enabled=false`, heap 512 MB |
| logstash | `logstash:8.14.0` | 5000 tcp/udp | elasticsearch | Lê `./logs/**/*.log` com codec JSON + TCP JSON |
| kibana | `kibana:8.14.0` | 5601 | elasticsearch | — |
| prometheus | `prom/prometheus:latest` | 9090 | — | Faz scrape de `gestor:8091/actuator/prometheus` e `gerar-insights:8080` |
| grafana | `grafana/grafana:latest` | 3000 | prometheus | `admin/admin` |

### 3.2 `docker-compose-local.yml` (build local, não versionado)
Variante mais enxuta (sem observabilidade) que faz build a partir de `./gestor-ativos-brutos` e `./gerar-insights`. Esses caminhos **não existem** dentro deste repositório (os projetos são pastas irmãs), então o build falha (`ISS-04`). O arquivo contém **chaves reais** da BRAPI e do Gemini (`ISS-01`).

### 3.3 Terraform (`infra/`)
- Provider AWS `~> 5.0` apontado para o LocalStack (`s3_use_path_style`, validações puladas).
- Módulos: `sqs` (3 filas: `tratar-ativos`, `sqs-iniciar-treinamento`, `sqs-registrar-series-historicas`), `s3` (`bucket-salvar-insights`, versionamento desligado, acesso público bloqueado, `force_destroy`), `sns` (`transmitir-lote-dados`).
- Parâmetros de fila: `delay 0`, `max 256 KB`, `retenção 1 dia`, `long polling 10 s`. **Sem DLQ, sem `visibility_timeout` explícito (padrão 30 s), sem criptografia.**
- `common_tags.CreatedAt = timestamp()` gera diff em todo `plan` (`ISS-10`).
- Estado local (`terraform.tfstate` no disco, ignorado pelo git); no container, o estado é efêmero.
- Imagem `infra/Dockerfile`: `hashicorp/terraform:latest` + aws-cli/jq, usuário não-root, `entrypoint.sh` com init → validate → plan → apply.

### 3.4 Schema MySQL (`mysql-init/1 - schema.sql`)
Cria `historico_acoes`, `insight_acao` e `serie_historica` (com `UNIQUE (simbolo, data_pregao, intervalo)`). É a **fonte de schema mais completa hoje** (inclui índices que as entidades ORM não declaram).

### 3.5 CI (`.github/workflows`)
- `01-feature-to-pr.yml`: abre PR `feature*` → `develop` automaticamente.
- `02-docker-build-push.yml`: em push para `develop` roda `terraform init -backend=false` + `validate` e publica `infra-b3-ecossystem` com as tags `develop`, `latest`, `sha` etc.
- O mesmo padrão existe nos dois serviços, **sem testes** antes da publicação.

---

## 4. Contratos entre serviços (fonte canônica)

| ID | Canal | Produtor → Consumidor | Formato / esquema | Garantias atuais |
|---|---|---|---|---|
| CTR-01 | SQS `tratar-ativos` | gestor → gerar-insights | JSON do `Ativo` (campos BRAPI em camelCase; ver `gestor#CTR-01`). Campos **obrigatórios para o consumidor**: `symbol`, `regularMarketPrice`, `earningsPerShare`. Usados: `priceEarnings`, `regularMarketOpen`, `regularMarketPreviousClose`, `regularMarketDayHigh/Low`, `regularMarketVolume`, `marketCap`, `fiftyTwoWeekLow/High` | Sem versão, sem atributo de deduplicação; `regularMarketTime` provavelmente nulo (`gestor#ISS-07`) |
| CTR-02 | SQS `sqs-registrar-series-historicas` | gestor → gerar-insights | `{results:[{symbol, requestedSymbol, data:{usedInterval, usedRange, historicalDataPrice:[{date(epoch s), open, high, low, close, adjustedClose, volume, dataFormatada}]}}], requestedAt, took}` | Idempotente no consumidor (upsert por dia) |
| CTR-03 | MySQL `insight_acao` | gerar-insights (escreve) → gestor (lê) | Colunas do `schema.sql`. `recomendacao` ∈ {`COMPRA_FORTE`, `COMPRA_MODERADA`, `VENDA_VALUATION`, `ALERTA_RISCO`, `MANTER`, `SEM_DADOS`}. `detalhes_json` v2.0; o gestor lê **apenas os campos numéricos de primeiro nível** (`earnings_yield_percent`, `desconto_maxima_52w_percent`, `crescimento_projetado_utilizado`) | Enum não compartilhado (`INT-01`); campos de primeiro nível não documentados como contrato |
| CTR-04 | S3 `bucket-salvar-insights` | gestor → clientes HTTP | `{simbolo}/analises/{HH:mm:ss}.json` com `RespostaAnaliseIaDTO` | Sobrescrita diária (`gestor#ISS-16`) |
| CTR-05 | MySQL `historico_acoes`, `serie_historica` | gerar-insights e ETL/COTAHIST (escrevem) | B3 é autoritativa na mesma chave e grava `fonte='B3'`; preços permanecem brutos e sinalizados como não ajustados | Leitura analítica futura; não usar preço bruto como ajustado |
| CTR-06 | MySQL `indicador_fundamentalista` | etl-fundamentos-cvm → gestor | Fundamentos contábeis derivados da CVM. Escrito **só** pelo ETL, lido **só** pelo gestor (`GET /analises/{simbolo}/fundamentos-cvm`). Chave natural `(simbolo, periodo, tipo_periodo)`. Métrica nula é deliberada quando o plano de contas da companhia não a comporta; a razão vai em `cobertura_json` | `P/L` e `P/VP` **não** são colunas: o gestor os deriva na leitura cruzando `lpa`/`vpa` com o preço de `historico_acoes`. `fato_contabil` é landing interna do ETL e **não** é contrato de leitura |
| CTR-07 | HTTP `GET /ativos/registrados` | gestor -> painel | Carteira monitorada. Alem da aba Monitorados, alimenta o seletor de ativos de todas as abas operacionais do painel | Virou contrato de navegacao: se cair, o front degrada para busca manual em vez de quebrar |
| CTR-08 | MySQL `comunicado_cvm` | etl-fundamentos-cvm (`--comunicados`) → gestor | Documentos eventuais da base IPE da CVM (dados abertos). Escrito **só** pelo ETL, lido **só** pelo gestor. Chave natural `protocolo_cvm` = `numProtocolo` do `link_download`; `protocolo_entrega` é informativo (vem vazio nos relatórios automáticos de proventos). Guarda **CNPJ**; ticker se obtém na leitura via `cvm_ticker`. `categoria` ∈ {`FATO_RELEVANTE`, `COMUNICADO_MERCADO`, `AVISO_ACIONISTAS`, `PROVENTOS`, `CALENDARIO_EVENTOS`, `RESULTADOS`, `ASSEMBLEIA`}; o texto cru fica em `categoria_original`. Por padrão só as seis primeiras são carregadas; `ASSEMBLEIA` é opcional | O conteúdo do documento **não** é copiado: só metadados e o link oficial. A base é republicada ~1x/semana; `data_entrega` máxima indica até quando há dado |
| CTR-09 | SQS `sqs-comunicados-publicados` | etl-fundamentos-cvm → (sem consumidor ainda) | Uma mensagem por ticker com documentos novos: `{schemaVersion:1, evento:"COMUNICADOS_PUBLICADOS", simbolo, cnpj, protocolos[], categorias[], dataEntregaMax}` | Falha em publicar não desfaz a carga: o dado já está no banco |
| CTR-10 | HTTP `GET /empresas/{simbolo}/comunicados`, `GET /comunicados/newsletter` | gestor → painel | Linha do tempo por ticker (filtros `categorias`, `desde`, `ate`, `pagina`, `tamanho`) e edição por período agrupada por ticker e ordenada por relevância (`FATO_RELEVANTE` > `PROVENTOS` > `RESULTADOS` > `COMUNICADO_MERCADO` > `AVISO_ACIONISTAS` > `CALENDARIO_EVENTOS` > `ASSEMBLEIA`). Toda resposta cita a fonte (`CVM - Dados Abertos (IPE)`) e `dadosAte` | Informativo, sem recomendação de investimento |

| CTR-11 | MySQL `sinal_diario`, `sinal_resultado` (V4) | gerar-insights (`python -m app.validacao.diario`) → gestor/painel (futuro) | Diário de sinais (paper trading). `sinal_diario` é **só inclusão**, chave `(simbolo, data_pregao, versao_regra)`: o sinal do pregão D é o último insight entre a abertura de D (10h BRT) e a abertura do pregão seguinte. `sinal_resultado` por horizonte (21/63/126 pregões): entrada na abertura do pregão seguinte, saída no fechamento; retorno bruto/líquido (custo 0,10% ida e volta), excesso sobre a média simples da carteira monitorada (mesmas datas, só ativos com preço nas duas pontas e sem salto suspeito, mínimo de 5; `ativos_na_carteira` registra quantos entraram; V5 trocou o BOVA11, que não é coletado) e sobre o CDI (SGS 12, histórico desde 2016 carregado pelo gestor), `acerto` nulo para recomendação sem direção, `evento_suspeito` para salto ≥ 40% (desdobramento em preço bruto) | A carteira carrega o viés de sobrevivência dos 31 monitorados; declarado na tela |
| CTR-12 | MySQL `ativo_identidade` (V6) + `GET /validacao/saude-dados` | curadoria na migration → gestor (registro), ETL (CNPJ, aliases do COTAHIST), gerar-insights (backtest) → painel | Um código canônico por empresa (`simbolo_canonico`); `continuidade_preco = 0` quando o código antigo não é o mesmo papel (BRFS3, JBSS3) e a série não pode ser emendada. Todo registro no gestor passa por `canonizar`. A saúde dos dados expõe idade de cada fonte contra o prazo da rotina, cobertura por ativo e divergência BRAPI × COTAHIST acima de 1% | Curadoria manual: ticker novo renomeado precisa de linha nova na migration |
| CTR-13 | MySQL `indicador_fundamentalista.data_entrega`, `cotacao_b3_diaria` (V6) | ETL → gerar-insights (diário v2 e backtest), gestor (saúde) | `data_entrega` = DT_RECEB da CVM da versão do documento usada (na dúvida, a mais tardia): nenhum consumidor pode usar balanço antes dela. `cotacao_b3_diaria` é o COTAHIST bruto com o código negociado no dia; quem lê junta pela identidade. Quantidade de ações validada entre anos (fator ~1000 corrige, pico isolado ≥5× anula LPA/VPA, motivo em `cobertura_json.validacao_acoes`) | Preço sem proventos |
| CTR-14 | MySQL `backtest_execucao`, `backtest_placar` (V6) + `GET /validacao/backtest` | gerar-insights (`python -m app.validacao.backtest`, sextas) → gestor → painel | Sinal mensal por ativo com dados point-in-time, v1 e v2, avaliado pelo mesmo motor do CTR-11. `periodo` CALIBRACAO (≤ corte, padrão 2022-12-31) ou TESTE; `taxa_base` já na direção da aposta. Cada execução deixa linha `BACKTEST` em `etl_execucao` | Viés de sobrevivência do universo atual |
| CTR-15 | `GET /ativos/{simbolo}/pregoes?de=&ate=&intervalo=dia\|semana\|mes` | gestor (lê `cotacao_b3_diaria` + `candle_diario`) → painel (aba Velas, períodos de 6 meses a desde 2016) | Símbolo antigo responde com o canônico e a série emendada pelos códigos de mesmo papel (CTR-12); na mesma data o canônico vence; dias que o COTAHIST ainda não trouxe vêm da BRAPI (`fonte`). Semana/mês: abertura do 1º pregão, fechamento do último, maior máxima, menor mínima. `saltos`: abertura ≥ 40% longe do fechamento anterior, medido no diário. `de` antes de 2016 é cortado; intervalo inválido ou `de > ate` → 400 | Preço bruto, sem proventos |

**Regra de evolução:** qualquer mudança em CTR-01..15 incrementa uma versão no payload (`schemaVersion` na mensagem SQS; `versao_payload` no `detalhes_json`), e o consumidor precisa aceitar a versão N e a N−1 durante a transição.

---

## 5. Requisitos

### 5.1 Funcionais (infra)

| ID | Requisito | Status |
|---|---|---|
| REQ-01 | Subir o ecossistema completo com um comando (`docker compose up -d`) | IMPLEMENTADO (com ressalvas `ISS-03`, `ISS-05`) |
| REQ-02 | Provisionar filas, bucket e tópico automaticamente antes dos serviços | IMPLEMENTADO |
| REQ-03 | Criar o schema MySQL de forma reprodutível, inclusive em bancos já existentes | IMPLEMENTADO com Flyway (2026-09-26) |
| REQ-04 | Ter logs e métricas dos dois serviços centralizados | PARCIAL (`ISS-08`, `INT-06`) |
| REQ-05 | Ambiente de desenvolvimento com build local dos serviços | NÃO FUNCIONAL (`ISS-04`) |

### 5.2 Não funcionais

| ID | Requisito | Status |
|---|---|---|
| NFR-01 | Nenhum segredo em arquivos do repositório ou no disco sem proteção | NÃO ATENDIDO (`ISS-01`) |
| NFR-02 | Versões de imagem fixadas (sem `latest`) para reprodutibilidade | NÃO ATENDIDO (`ISS-05`) |
| NFR-03 | Toda fila de trabalho com DLQ e `visibility_timeout` adequado | ATENDIDO (2026-09-26) |
| NFR-04 | Entrega *at-least-once* tratada com idempotência ponta a ponta | NÃO ATENDIDO (`INT-03`) |
| NFR-05 | Schema com dono único e migrations versionadas | NÃO ATENDIDO (`INT-04`) |
| NFR-06 | O ecossistema sobe em máquina de 8 GB de RAM (perfil sem ELK opcional) | A VERIFICAR (`ISS-09`) |

---

## 6. Problemas identificados

### 6.1 Integração entre serviços (`INT-`)

| ID | Sev. | Problema | Evidência | Impacto | Correção sugerida | Status |
|---|---|---|---|---|---|---|
| INT-01 | Alto | Enum de recomendação não compartilhado: o gestor conta `"VENDA"`, o Python emite `"VENDA_VALUATION"` | `gestor: tools/ConsolidadorAnaliseAcao.java` × `gerar-insights: app/core/analysis/recommendation.py` | `perc_venda` sempre 0 no prompt do Gemini | Declarar o enum em CTR-03; testes de contrato nos dois lados | ABERTO |
| INT-02 | Alto | Corrida: o gestor publica e lê `insight_acao` em seguida | `gestor: service/ServicoAtivo.java` | A análise de IA ignora o dado do dia; na primeira coleta não há análise | Evento "insight gerado" (usar o SNS `transmitir-lote-dados` ou uma fila `insight-gerado`) que dispara a análise | ABERTO |
| INT-03 | Alto | Nenhuma idempotência ponta a ponta: GET com efeito colateral + fila *at-least-once* + inserts sem chave natural | `gestor#ISS-09`, `gerar-insights#ISS-02` | `historico_acoes`/`insight_acao` duplicados distorcem a consolidação (sinal predominante contado N vezes) | `dedupKey = symbol + regularMarketTime` como atributo da mensagem + `UNIQUE` no banco | ABERTO |
| INT-04 | Alto | Três donos de schema: `mysql-init` (infra), Hibernate `ddl-auto=update` (gestor), entidades SQLAlchemy (Python) | `mysql-init/1 - schema.sql`, `gestor application-*.properties` | Drift; o Hibernate pode alterar a tabela `insight_acao` do Python | Dono único: migrations versionadas (Flyway ou Alembic) em um lugar; gestor com `validate`; `mysql-init` só para bootstrap | ABERTO |
| INT-05 | Médio | O gestor depende de campos de primeiro nível de `detalhes_json` que a spec do Python classificava como "legado" | `gestor: ConsolidadorAnaliseAcao.consolidarIndicadores` | Removê-los no Python quebra a análise de IA sem erro visível | Formalizados em CTR-03; `gerar-insights` não pode removê-los sem nova versão | ABERTO |
| INT-06 | Médio | Observabilidade assimétrica: Python sem `/metrics` e com logs só em stdout (fora do ELK); Java loga em texto num arquivo lido como JSON **e** via TCP (duplicado) | `prometheus.yml`, `logstash.conf`, `gestor logback-spring.xml` | Target `gerar-insights` sempre *down*; logs duplicados ou quebrados no Kibana | Python: `prometheus_client` em :8080 + logs JSON; Java: JSON só via TCP; remover o input de arquivo **ou** padronizar arquivos JSON | ABERTO |
| INT-07 | Médio | Timestamp da cotação perdido no contrato (`regularMarketTime`) | `gestor#ISS-07` | Impossível deduplicar por pregão ou ordenar corretamente | ISO-8601 UTC obrigatório em CTR-01 | ABERTO |
| INT-08 | Baixo | Recursos provisionados sem uso: `sqs-iniciar-treinamento`, SNS `transmitir-lote-dados` | `infra/main.tf` | Ruído/confusão | Documentar o uso planejado (DEC-03) ou remover | ABERTO |

### 6.2 Infraestrutura e Docker (`ISS-`)

| ID | Sev. | Problema | Evidência | Impacto | Correção sugerida | Status |
|---|---|---|---|---|---|---|
| ISS-01 | **Crítico** | Chaves reais BRAPI/Gemini em texto puro | `docker-compose-local.yml` (não versionado, mas sem proteção no `.gitignore`); também em `gestor/src/main/resources/application-test.properties` | Vazamento no primeiro `git add .` | Revogar e gerar novas chaves; mover para `.env` (listado no `.gitignore`) com `env_file`; adicionar `docker-compose-local.yml`/`.env` ao `.gitignore` ou usar só `${VAR}`; gitleaks no CI | ABERTO |
| ISS-02 | Alto | Filas sem DLQ e sem `visibility_timeout`/`redrive_policy` | Módulo cria uma DLQ por fila, `maxReceiveCount=5`, retenção de 14 dias e visibilidade de 120 s | Mensagem venenosa é isolada | Validar no LocalStack após apply | CONCLUIDO (2026-09-26) |
| ISS-03 | Alto | `mysql-init` só roda com volume vazio | Compose executa Flyway one-shot com migrations versionadas e o gestor valida o schema | Bancos existentes recebem as colunas e índices novos | Migração V2 é idempotente | CONCLUIDO (2026-09-26) |
| ISS-04 | Alto | `docker-compose-local.yml` aponta para contextos de build inexistentes (`./gestor-ativos-brutos`, `./gerar-insights`) | `docker-compose-local.yml` | Ambiente de desenvolvimento local não sobe | `context: ../gestor-ativos-brutos/gestor-ativos-brutos` e `../gerar-insights/gerar-insights`, ou variável `ECOSYSTEM_ROOT`; usar `docker-compose.override.yml` para builds locais | ABERTO |
| ISS-05 | Médio | Imagens `latest` (serviços, prometheus, grafana, terraform) e tag `latest` publicada a partir de `develop` | `docker-compose.yml`, workflows | Build não reproduzível; `develop` quebrado vira `latest` | Fixar versões/digests; `latest` só a partir de tag semver em `main` | ABERTO |
| ISS-06 | Médio | O compose sobrescreve o `entrypoint.sh` do provisionador, pulando `validate`/`plan` e os logs estruturados | `docker-compose.yml` (`entrypoint: terraform init && apply`) | Perde as validações que a imagem oferece | Remover o override e usar o `ENTRYPOINT` da imagem | ABERTO |
| ISS-07 | Médio | Credenciais e flags inseguras: Grafana `admin/admin`, Elasticsearch sem segurança, LocalStack `DEBUG=1`, MySQL `root/root`, todas as portas expostas no host | `docker-compose.yml` | Aceitável só em máquina local; perigoso se reaproveitado em servidor | Variáveis em `.env`; bind em `127.0.0.1:`; marcar o compose como "somente dev" | ABERTO |
| ISS-08 | Médio | `gerar-insights` expõe 8080 e o Prometheus faz scrape dele, mas o worker não tem HTTP | `docker-compose.yml`, `prometheus.yml` | Target sempre *down*; porta enganosa | Implementar `/metrics` e `/health` no worker (INT-06) ou remover porta e job | ABERTO |
| ISS-09 | Médio | Pilha pesada: ES + Logstash + Kibana + Prometheus + Grafana + 2 JVMs (≈ 3–4 GB RAM) sempre ligados | `docker-compose.yml` | Máquina de desenvolvimento lenta | Compose `profiles` (`core`, `observability`); `docker compose --profile observability up` quando necessário | ABERTO |
| ISS-10 | Baixo | `CreatedAt = timestamp()` nas tags causa diff permanente | `infra/locals.tf` | `plan` nunca fica limpo | Remover a tag ou usar `lifecycle { ignore_changes = [tags["CreatedAt"]] }` | ABERTO |
| ISS-11 | Baixo | Healthcheck do MySQL no compose local sem credenciais; `gestor` espera só `service_started` | `docker-compose-local.yml` | Java pode subir antes do banco estar pronto | Mesmo healthcheck do compose principal + `service_healthy` | ABERTO |
| ISS-12 | Baixo | CI da infra publica imagem sem `terraform fmt -check`, tflint ou checkov | `.github/workflows/02-docker-build-push.yml` | Qualidade e segurança do IaC não verificadas | Adicionar fmt/tflint/checkov | ABERTO |
| ISS-13 | Médio | Trabalho não commitado nos **três** repositórios, em branches `feature-*` diferentes | `git status` de cada repo | Mudanças de contrato (série histórica, nova fila e tabela) podem ser integradas fora de ordem | Ordem de merge: infra (fila e tabela) → gerar-insights (consumidor) → gestor (produtor) | ABERTO |

---

## 7. Roadmap do ecossistema

### Fase 0 — Segurança e ambiente que sobe (bloqueante)

| ID | Tarefa | Resolve | Repos | Critério de aceite | Status |
|---|---|---|---|---|---|
| TASK-01 | Revogar e gerar novas chaves BRAPI/Gemini; `.env` + `.env.example`; gitleaks nos 3 CIs | ISS-01, NFR-01 | infra, gestor | Nenhum segredo em `git grep`; pipeline bloqueia segredo | ABERTO |
| TASK-25 | Série histórica longa via COTAHIST da B3, quebrando o teto de 3 meses da BRAPI | CTR-05 | infra, etl | Carga filtra ativos monitorados, divide preços por 100 e grava `fonte='B3'` | CONCLUIDO (2026-09-26) |
| TASK-26 | Decidir e implementar o ajuste por proventos da série do COTAHIST (a fonte entrega preço bruto) | TASK-20 | etl | Fonte estruturada oficial identificada no UP2DATA, sem contrato gratuito confirmado; série permanece bruta e explicitamente sinalizada | BLOQUEADO por fonte/licença |
| TASK-27 | Registrar em CTR-05 o segundo escritor de `serie_historica` (B3 além de BRAPI) e a regra de precedência | TASK-20 | infra | CTR-05 nomeia os dois escritores e diz qual vence na mesma chave | CONCLUIDO (2026-09-26) |
| TASK-02 | Corrigir os contextos de build do compose local e usar o mesmo healthcheck | ISS-04, ISS-11 | infra | `docker compose -f docker-compose-local.yml up --build` sobe tudo *healthy* | ABERTO |
| TASK-03 | Serviço one-shot `db-migrate` (Flyway) que aplica o schema de forma idempotente | ISS-03, INT-04 | infra | Com volume antigo, colunas e índices novos existem após `up` | CONCLUIDO (2026-09-26) |
| TASK-04 | Merge coordenado das features pendentes na ordem infra → gerar-insights → gestor | ISS-13 | todos | Os 3 repos com `git status` limpo e PRs mergeados em `develop` | ABERTO |

### Fase 1 — Contratos e confiabilidade

| ID | Tarefa | Resolve | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|---|
| TASK-10 | DLQ + `visibility_timeout` + retenção no módulo SQS | ISS-02, NFR-03 | infra, gerar-insights | Mensagem que falha 5× vai para `<fila>-dlq` | — | CONCLUIDO (2026-09-26) |
| TASK-11 | Enum de recomendações + `schemaVersion` + JSON Schema dos payloads em `contracts/` neste repo | INT-01, INT-05, CTR-01..03 | todos | Testes de contrato nos dois serviços validam contra `contracts/*.schema.json` | — | ABERTO |
| TASK-12 | Idempotência ponta a ponta (`dedupKey`, `UNIQUE`, GET sem efeito colateral) | INT-03, INT-07, NFR-04 | todos | Reenviar a mesma mensagem 3× gera 1 linha | TASK-11 | ABERTO |
| TASK-13 | Dono único de schema com migrations; gestor em `ddl-auto=validate` | INT-04, NFR-05 | todos | DEC-01 registrada; startup falha se houver drift | DEC-01 | ABERTO |
| TASK-14 | Evento "insight gerado" desacoplando a análise de IA | INT-02 | todos | Análise S3 criada **depois** do insight do dia | DEC-02 | ABERTO |

### Fase 2 — Operação

| ID | Tarefa | Resolve | Critério de aceite | Status |
|---|---|---|---|---|
| TASK-20 | Compose `profiles` (core / observability) e bind em 127.0.0.1 | ISS-07, ISS-09 | `docker compose up` sem profile sobe só o core | ABERTO |
| TASK-21 | Observabilidade uniforme: métricas e logs JSON do Python; logs do Java sem duplicação; dashboards Grafana provisionados | INT-06, ISS-08 | Os 2 targets *up* no Prometheus; 1 evento = 1 documento no ES | ABERTO |
| TASK-22 | Fixar versões de imagem; `latest` só em release | ISS-05 | Nenhum `:latest` no compose | ABERTO |
| TASK-23 | Usar o `entrypoint.sh` do provisionador; remover `timestamp()` das tags; fmt/tflint/checkov no CI | ISS-06, ISS-10, ISS-12 | `terraform plan` limpo na 2ª execução | ABERTO |
| TASK-24 | Decidir e implementar/remover `sqs-iniciar-treinamento` e SNS | INT-08 | DEC-03 registrada | ABERTO |

### Fase 3 — Precisão e confiabilidade (plano de 2026-09-27)

Ponto de partida medido: dados 31/31 com preço, balanço, data de entrega e TTM; regra oficial v1 `2026.09.27-2` com compras raras e com vantagem ainda não significativa (teste, 63 pregões: 24 janelas, 58% contra taxa-base de 52%), vendas sem vantagem e fração de vendas dependente do regime de juros (`gerar-insights#DEC-07`). Ordem sugerida: TASK-43 e TASK-30 → TASK-31 (+ TASK-39, TASK-40 em paralelo) → TASK-34, 35, 37, 38 → TASK-32, 33, 41, 42, 44.

**Onda 1 — medir melhor (precisão estatística)**

| ID | Tarefa | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|
| TASK-30 | Intervalo de confiança em todo placar: Wilson 95% para o acerto, média ± 1,96·erro-padrão para o excesso; "acima/abaixo da base" só quando o intervalo não cruza a taxa-base | gerar-insights, gestor, painel, infra (V9) | Painel mostra "58% (46–69%)"; linha sem significância aparece como "indistinguível da base" | — | CONCLUIDO (2026-09-27): V9, `tools/IntervaloConfianca` (gestor), `agregar` com desvio (gerar-insights), leitura no painel. Supõe janelas independentes — ver TASK-31 |
| TASK-31 | Universo de backtest amplo e sem viés de sobrevivência: ações de lote padrão com ≥ 200 pregões e liquidez mínima **no ano anterior**, incluindo deslistadas, a partir do COTAHIST e dos DFP em cache; régua de mercado = média desse universo | etl, infra, gerar-insights | ≥ 3× janelas; deslistadas incluídas; intervalo de confiança por bootstrap em blocos (janelas sobrepostas e ativos correlacionados deixam o intervalo de TASK-30 otimista); cobertura de CNPJ por ano exibida; backtest < 5 min | TASK-30, **gerar-insights#TASK-59** | CONCLUIDO (2026-09-27): COTAHIST amplo 2016-2026 (1.785 códigos, 1,16 mi pregões); universo point-in-time em `app/validacao/universo.py` (≥ 200 pregões e ≥ R$ 5 mi/dia no ano anterior, sem units nem BDRs, com deslistadas): 93 a 191 ações por ano; DFP 2016-2025 de 249 empresas (`etl --universo-backtest`); backtest com 258 ativos, 15.732 amostras (5×); IC por bootstrap em blocos de meses (V12, `bootstrap.py`). **Resultado: nenhuma regra com vantagem distinguível** — acerto e excesso cruzam a base em todas as linhas, exceto a compra moderada da v1 antiga (+1,1% s/ carteira, IC +0,3 a +2,0). 38 papéis sem balanço por troca de código: `infra#TASK-45` |
| TASK-32 | Sinais técnicos (momentum, reversão à média) avaliados no backtest como regras próprias | gerar-insights | Placar próprio; entram na recomendação só com vantagem nos dois períodos (DEC) | TASK-31 | ABERTO |
| TASK-33 | Curva de calibração do score de confiança (acerto real por faixa de score) | gerar-insights, gestor, painel | Gráfico no painel; DEC: recalibrar ou retirar o score | TASK-31 | ABERTO |

**Onda 2 — corrigir a regra (precisão do modelo)**

| ID | Tarefa | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|
| TASK-34 | Crescimento nominal na v1 (g real + IPCA 12m) contra Y real (Selic − IPCA), escolhido por backtest | gerar-insights | Fração de vendas varia < 10 p.p. entre calibração e teste; separação não piora; DEC | TASK-31 | CONCLUIDO (2026-09-27): G_NOMINAL adotado (`gerar-insights#DEC-08`); vendas 20% → 32% entre calibração e teste (11,6 p.p., aceite era < 10) |
| TASK-35 | `VENDA_VALUATION` vira `SEM_MARGEM` (sem direção) enquanto não houver vantagem medida com IC | gerar-insights, gestor, painel | Contrato de recomendações versionado (INT-01); tela sem "venda" generalizada | TASK-30 | ABERTO |
| TASK-36 | Proventos: retorno e régua com proventos (feito: `gerar-insights` 7ea0d1e, 13b6287); contagem `janelas_com_provento` no placar (V10, `gerar-insights#TASK-56`); falta o histórico além dos ~12 meses que a B3 devolve por consulta (`gerar-insights#TASK-46`) | gestor, gerar-insights | Placar diz quantas janelas foram ajustadas; histórico com fonte registrada em DEC | — | PARCIAL |
| TASK-37 | Recalibrar limiares no universo amplo, objetivo pelo limite inferior do IC | gerar-insights | DEC com limiares e intervalo | TASK-31, TASK-34 | CONCLUIDO (2026-09-27), sem mudança de limiares — ver `gerar-insights#DEC-09`: nenhuma das 1.944 combinações válidas teve o limite inferior do IC da separação acima de zero na calibração (melhor: −2,1 a +3,2 p.p.) |
| TASK-38 | Decidir v1 × v2 pelos números (a vencedora nos dois períodos, com IC, vira a oficial) | gerar-insights | DEC com números; `VERSAO_REGRA` incrementada | TASK-37 | ABERTO |

**Onda 3 — confiabilidade operacional**

| ID | Tarefa | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|
| TASK-39 | Checagens de dados depois de cada carga (lucro zero com receita, LPA fora da mediana, balanço sem data de entrega, salto sem evento, papel sem CNPJ, BRAPI × COTAHIST) gravadas em `checagem_dados`; severidade ERRO vira ERRO na saúde dos dados | etl, infra (migração nova), gestor | O caso TIMS3 (lucro 0) é pego sozinho; teste de regressão | — | ABERTO |
| TASK-40 | Alerta ativo: `checar-saude.ps1` diário lê `/validacao/saude-dados` e avisa por Telegram no estado PROBLEMA; grava `saude_dados_historico` | infra, gestor | Falha provocada chega ao celular (bot criado pelo usuário) | — | ABERTO |
| TASK-41 | Backup fora da máquina (pasta sincronizada ou disco externo), semanal, com restauração mensal testada a partir da cópia | infra | Restauração da cópia registrada na saúde dos dados | — | ABERTO |
| TASK-42 | CI com teste, lint e tipos antes do build nos 5 repositórios; corrigir o teste `>Formulas<` do painel | todos | Pipeline vermelho bloqueia a imagem | — | ABERTO |
| TASK-43 | Protocolo de trabalho paralelo entre sessões/agentes (regra 6 da seção 1) | infra | Regra escrita; nenhum commit misturado depois dela | — | CONCLUIDO (2026-09-27) |
| TASK-44 | Sequência de dias com a saúde dos dados verde, na aba Avaliação | gestor, painel | Evidência para a nota de confiabilidade 7 | TASK-40 | ABERTO |
| TASK-45 | Curadoria de códigos renomeados do universo amplo na `ativo_identidade` (VIIA3→BHIA3, KROT3→COGN3, BTOW3/AMER3, SUZB5→SUZB3, VALE5, RUMO3→RAIL3, CLSA3, DMMO3…): 38 dos 258 papéis do backtest ficaram sem balanço porque o FCA não liga o código antigo ao CNPJ | etl, infra (migração nova) | Lista de "sem nenhum balanço" nas observações do backtest cai para perto de zero | TASK-31 | ABERTO |

---

## 8. Decisões

| ID | Pergunta | Opções | Recomendação da análise | Status |
|---|---|---|---|---|
| DEC-01 | Dono do schema MySQL | (a) infra (`mysql-init` + Flyway/Liquibase); (b) gerar-insights (Alembic), que é quem escreve; (c) gestor (Flyway) | (b) ou (a): quem escreve define; o gestor só valida | ABERTO |
| DEC-02 | Gatilho da análise de IA | síncrono / evento SNS pós-insight / agendamento | Evento pós-insight | ABERTO |
| DEC-03 | Destino de `sqs-iniciar-treinamento` e do SNS `transmitir-lote-dados` | manter com caso de uso documentado / remover | Usar o SNS no DEC-02; remover a fila de treinamento até existir consumidor | ABERTO |
| DEC-04 | Onde ficam os contratos (JSON Schema) | este repo (`contracts/`) / repo próprio / cada serviço | Este repo, por já ser o "dono" do ecossistema | ABERTO |
| DEC-05 | Ambiente alvo além do local | só local / AWS real (dev/homolog/prod já previstos em `var.environment`) | Definir antes de TASK-13 do gestor (credenciais) | ABERTO |

---

## 9. Comandos de verificação

```bash
# subir o core + observabilidade
docker compose up -d
docker compose ps

# provisionamento
docker logs my-terraform-provisioner
awslocal sqs list-queues
awslocal s3 ls

# schema
docker exec -it mysql mysql -uspring -pspring123 minha_base -e "SHOW TABLES;"

# fluxo ponta a ponta
curl http://localhost:8091/ativos/PETR4
docker logs -f gerar-insights
docker exec -it mysql mysql -uspring -pspring123 minha_base \
  -e "SELECT simbolo, recomendacao, data_analise FROM insight_acao ORDER BY id DESC LIMIT 5;"

# observabilidade
# Prometheus: http://localhost:9090/targets · Grafana: http://localhost:3000 · Kibana: http://localhost:5601
```
