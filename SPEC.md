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

---

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
| CTR-05 | MySQL `historico_acoes`, `serie_historica` | gerar-insights (escreve) | `schema.sql` | Sem leitores hoje |

**Regra de evolução:** qualquer mudança em CTR-01..05 incrementa uma versão no payload (`schemaVersion` na mensagem SQS; `versao_payload` no `detalhes_json`), e o consumidor precisa aceitar a versão N e a N−1 durante a transição.

---

## 5. Requisitos

### 5.1 Funcionais (infra)

| ID | Requisito | Status |
|---|---|---|
| REQ-01 | Subir o ecossistema completo com um comando (`docker compose up -d`) | IMPLEMENTADO (com ressalvas `ISS-03`, `ISS-05`) |
| REQ-02 | Provisionar filas, bucket e tópico automaticamente antes dos serviços | IMPLEMENTADO |
| REQ-03 | Criar o schema MySQL de forma reprodutível, inclusive em bancos já existentes | PARCIAL (`ISS-03`) |
| REQ-04 | Ter logs e métricas dos dois serviços centralizados | PARCIAL (`ISS-08`, `INT-06`) |
| REQ-05 | Ambiente de desenvolvimento com build local dos serviços | NÃO FUNCIONAL (`ISS-04`) |

### 5.2 Não funcionais

| ID | Requisito | Status |
|---|---|---|
| NFR-01 | Nenhum segredo em arquivos do repositório ou no disco sem proteção | NÃO ATENDIDO (`ISS-01`) |
| NFR-02 | Versões de imagem fixadas (sem `latest`) para reprodutibilidade | NÃO ATENDIDO (`ISS-05`) |
| NFR-03 | Toda fila de trabalho com DLQ e `visibility_timeout` adequado | NÃO ATENDIDO (`ISS-02`) |
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
| ISS-02 | Alto | Filas sem DLQ e sem `visibility_timeout`/`redrive_policy` | `infra/sqs/main.tf`, `infra/locals.tf` | Mensagem venenosa em loop por até 1 dia e depois perdida | Módulo SQS com DLQ opcional (`maxReceiveCount=5`), retenção de 4 a 14 dias na DLQ, `visibility_timeout` ≥ 6× o tempo de processamento | ABERTO |
| ISS-03 | Alto | `mysql-init` só roda com volume vazio; a nova tabela `serie_historica` não é criada em ambientes que já existem | comportamento da imagem `mysql:8.0` + volume `mysql_data` | Worker Python falha ao gravar a série (erro de tabela inexistente → mensagem em retry infinito) | Migrations versionadas (INT-04) ou documentar `docker compose down -v`; script idempotente executado por um serviço one-shot `db-migrate` | ABERTO |
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
| TASK-02 | Corrigir os contextos de build do compose local e usar o mesmo healthcheck | ISS-04, ISS-11 | infra | `docker compose -f docker-compose-local.yml up --build` sobe tudo *healthy* | ABERTO |
| TASK-03 | Serviço one-shot `db-migrate` (ou Flyway) que aplica o schema de forma idempotente | ISS-03, INT-04 | infra | Com volume antigo, `serie_historica` existe após `up` | ABERTO |
| TASK-04 | Merge coordenado das features pendentes na ordem infra → gerar-insights → gestor | ISS-13 | todos | Os 3 repos com `git status` limpo e PRs mergeados em `develop` | ABERTO |

### Fase 1 — Contratos e confiabilidade

| ID | Tarefa | Resolve | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|---|
| TASK-10 | DLQ + `visibility_timeout` + retenção no módulo SQS | ISS-02, NFR-03 | infra, gerar-insights | Mensagem que falha 5× vai para `<fila>-dlq` | — | ABERTO |
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
