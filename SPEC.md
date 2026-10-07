# SPEC — Ecossistema B3 Monitoring (Infraestrutura, Docker e Integração)

| Campo | Valor |
|---|---|
| Versão da spec | 1.0.0 |
| Data | 2026-09-27 |
| Status | IMPLEMENTADO |
| Escopo | Este repositório **e** a integração entre `gestor-ativos-brutos` (Java) e `gerar-insights` (Python) |
| Specs dos serviços | `gestor-ativos-brutos/SPEC.md` · `gerar-insights/SPEC.md` |
| Público | Desenvolvedores humanos e agentes de IA (Codex, ChatGPT, Claude ou outros) |

---

## Corte e estados comuns

Data de corte: **2026-09-27** (America/Sao_Paulo). `PLANEJADO`: ainda não executado; `EM ANDAMENTO`: entrega parcial; `IMPLEMENTADO`: código ou decisão presente, sem confirmação integral nesta revisão; `VERIFICADO`: aceite demonstrado por verificação registrada; `BLOQUEADO`: dependência impeditiva identificada. Datas anteriores permanecem como histórico. Resolver um problema significa implementar sua correção; funcionalidades descontinuadas mantêm o ID e registram a resolução. Evidências antigas não são nova validação operacional.

## 1. Como usar este arquivo (protocolo para agentes)

Esta é a **spec de nível de sistema**. Ela é dona de:
- **contratos entre serviços** (`CTR-`): filas, payloads, tabelas compartilhadas, bucket;
- **topologia Docker/Terraform** (`REQ-`, `NFR-`, `ISS-` deste repositório);
- **problemas de integração** (`INT-`), que afetam mais de um repositório.

Regras:
1. Fluxo SDD: `Spec → Plano → Tarefas → Implementação → Verificação → Atualizar Spec`.
2. Uma mudança de contrato (`CTR-`) só pode ser implementada depois que esta spec estiver atualizada, e precisa de uma tarefa correspondente **em cada** repositório afetado.
3. Para referenciar IDs de outras specs, use o prefixo do repositório: `gerar-insights#ISS-01`, `gestor#ISS-02`, `infra#ISS-03`.
4. IDs são estáveis; para descontinuar, use o status `IMPLEMENTADO (descontinuado)` com justificativa. Decisões viram `DEC-`.
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

## 1A. Central de coordenação entre agentes (HUB)

**Este arquivo é o ponto de comunicação entre agentes de IA distintos.** Os `SPEC.md` dos outros 4 repositórios têm um bloco "Coordenação" que aponta para cá e traz só a fatia local da fila. Em conflito entre seções antigas deste arquivo e esta seção 1A, **vale a 1A** (estado em 2026-10-04); as seções 2–9 são histórico detalhado e serão podadas conforme as tarefas fecharem.

### 1A.1 Como um agente entra e sai (handoff)

1. **Entrar:** leia a 1A inteira → `git status` do repositório → leia o `SPEC.md` do repositório que vai tocar. Alteração não commitada que não é sua pertence a outro agente: não edite nem commite.
2. **Pegar tarefa:** na fila (1A.4), troque o estado para `EM ANDAMENTO (<agente>/<branch>, <data>)` **e faça commit só dessa linha** antes de codar. Marca de outro agente = tarefa ocupada.
3. **Contrato novo ou alterado (`CTR-`):** atualize 1A.5 e a tarefa correspondente em cada repositório afetado antes de implementar.
4. **Sair:** commit + push só dos seus arquivos (`git add <arquivo>`, nunca `-A`); mude o estado na fila para `IMPLEMENTADO` (ou `VERIFICADO` se houver evidência: comando + resultado); acrescente uma linha no diário (1A.7) com o que ficou pendente e qualquer comando que o próximo agente precise rodar.
5. **Bloqueio:** estado `BLOQUEADO (motivo, quem desbloqueia)`; nunca deixe tarefa `EM ANDAMENTO` sem agente ativo — o diário é a prova de vida (marca sem entrada há mais de 2 dias pode ser reassumida avisando no diário).
6. PRs abrem sozinhos a partir de `feature-*`; não abrir PR manual. Commit só em `feature-*` (crie a partir de `main` se preciso).

### 1A.2 Repositórios, dono e estado (2026-10-04)

| Repo | Stack | Branch ativa | Dono dos arquivos | Spec |
|---|---|---|---|---|
| `infra-b3-ecossytem` | Compose, Terraform/LocalStack, Flyway, scripts PowerShell | `feature-nova-infra` | schema (`mysql-migrations/`), `contracts/`, `scripts/`, compose | este arquivo |
| `gestor-ativos-brutos` | Java 21 / Spring Boot 3.3 | `feature-teste` | API HTTP, coleta BRAPI, scheduler, leitura de `insight_acao` | `gestor-ativos-brutos/gestor-ativos-brutos/SPEC.md` |
| `gerar-insights` | Python (worker + CLIs de validação) | `feature-migrate` | `insight_acao`, diário, backtest, fatores LAC | `gerar-insights/gerar-insights/SPEC.md` |
| `etl-fundamentos-cvm` | Python hexagonal | `feature-comunicados-cvm` | fundamentos, TTM, comunicados, COTAHIST, DVA, conciliação | `etl-fundamentos-cvm/SPEC.md` |
| `painel-ativos-frontend` | Node/Express + Web Components | `feature-comunicados-cvm` | UI; só consome HTTP do gestor | `painel-ativos-frontend/SPEC.md` |

Regra de propriedade de dados: **só o Flyway cria/altera tabelas** (`ddl-auto=validate`; migration aplicada nunca é editada — corrigir com nova versão). Cada tabela tem um escritor; os demais só leem.

### 1A.3 Estado atual do sistema (verdade de 2026-10-04; supera seções antigas)

- **Migrations:** V1 baseline … V16 aplicadas no MySQL local (V11 foi renomeada V14; histórico reparado). Lista: V1 baseline, V2 deduplicação, V3 comunicados CVM, V4 diário de sinais, V5 diário/benchmark, V6 identidade+ponto-no-tempo+backtest, V7 tabelas JPA do gestor, V8 provento distribuído, V9 placar IC, V10 janelas com provento, V12 IC bootstrap, V13 monitoramento em camadas, V14 inbox de eventos, V15 consumo BRAPI + conciliação, V16 Plano LAC. (O baseline e `contracts/` ainda estão **não commitados** — ver T-INFRA-01.)
- **Monitoramento em camadas (V13):** `COTACAO_E_HISTORICO` = favorito (BRAPI intradiária, mínimo 900 s, 10:05–17:35, máx. 35); `REFERENCIA_DIARIA` e legado `COTACAO` = sem BRAPI (preço oficial vem do COTAHIST).
- **Rotina diária (Plano de atualização, `PLANO-ATUALIZACAO-DIARIA.md`):** Frente A infra (Garantir-Stack, rotina da manhã, restart policies, provisioner com build) ✔; Frente B gestor (orçamento BRAPI, ciclo intradiário, snapshot 17:40) ✔; Frente C insights/ETL (`--recuperar`, `--conciliar`) ✔. O gatilho "ao logon (+5 min)" **não pôde ser registrado no sandbox** (ONLOGON negado; só DAILY/WEEKLY) — registrar manualmente fora do sandbox.
- **Fluxo de eventos:** gestor → SQS (`schemaVersion 1.0`, `dedupKey`) → worker valida schema, inbox `evento_processado` (V14) e efeito na mesma transação, ACK após commit. Payload inválido fica para a DLQ.
- **Análise:** só regras determinísticas (Graham etc.); Gemini/S3 **descontinuados** (recursos Terraform podem sobrar). Backtest: nenhuma regra tem vantagem distinguível (DEC-07/08/09 no `gerar-insights`) — toda tela mantém aviso de regra **experimental**.
- **Endpoints do gestor hoje (contrato com o painel):** `/ativos/registrados`, `/ativos/robusto/{s}`, `/ativos/registrar/{s}`, `/ativos/{s}/pregoes`, `/ativos/{s}/fatores`, `/ativos/{s}/proventos-contabeis`, `/analises/{s}/analise|fundamentos|fundamentos-cvm`, `/empresas/{s}/comunicados`, `/comunicados/newsletter`, `/setores`, `/indices-macro/{c}`, `/validacao/diario|saude-dados|backtest[?metodo=RANKING]`, favoritos e camada Base (detalhe no SPEC do gestor). GETs não gravam nem publicam.
- **Imagens locais:** a stack local usa as imagens do Docker Hub tag `develop`; atualizar sem derrubar MySQL: `docker compose pull <serviço>` + `up -d --no-deps <serviço>`. A imagem `etl:develop` pode não conter ainda `--conciliar` (conferir antes de agendar).
- **Artefatos de build local:** quando o Maven não alcança o Central (TLS), compilar com `javac --release 21 -parameters` contra o classpath do jar do container e aplicar hot-patch — é contingência, não processo.

### 1A.4 Fila de trabalho (única; atualizar aqui)

Estados: `PLANEJADO` · `EM ANDAMENTO (agente/branch, data)` · `IMPLEMENTADO` · `VERIFICADO` · `BLOQUEADO (motivo)`. Prioridade: P0 quebra o sistema, P1 valor direto, P2 melhoria.

| ID | Repo | Pri | Tarefa | Depende | Estado |
|---|---|---|---|---|---|
| T-INFRA-01 | infra | P0 | Commitar o que está solto: `mysql-migrations/V1__baseline.sql`, remoção de `mysql-init/1 - schema.sql`, `contracts/`, `scripts/sincronizar-contratos.mjs`, `compose.contract-tests.yml`, `infra/s3/main.tf` — pertencem à sessão de contratos; **perguntar antes** | — | PLANEJADO |
| T-INFRA-02 / TASK-E20 | infra | P1 | Registrar fora do sandbox a tarefa "ao logon +5 min" da rotina da manhã; `StartWhenAvailable` na rotina e no backup (ISS-E15 do ETL) | Frente A | BLOQUEADO (script pronto; o usuário precisa rodar `scripts
egistrar-rotinas.ps1` num PowerShell fora do app Claude — Sessão 03, 2026-10-07) |
| TASK-E21 | infra | P1 | Logs/backups fora da virtualização MSIX do app Claude; dump pré-V16 para a pasta real; `Garantir-Stack` no backup (ISS-E16 do ETL) | — | IMPLEMENTADO (Sessão 03, 2026-10-07): pasta em `%USERPROFILE%3-ecossistema`; dump pré-V16 copiado e conferido (descompacta até "Dump completed"); backup chama `Garantir-Stack`; rotação ignora dumps nomeados. Falta ver um backup agendado gravar na pasta nova |
| TASK-E19 | etl | P1 | Nova tentativa no `ClienteHttpCvm` (ISS-E14) | — | IMPLEMENTADO (3dd1687 Codex + 6ed1929 UP038, Sessão 03, 2026-10-07): retry 5 s/15 s só para 5xx/429/timeout/conexão; `ClienteHttpB3` herda |
| T-INFRA-03 | infra | P1 | Publicar imagens `develop` atualizadas e conferir que `etl` tem `--conciliar` e `--proventos` | — | PLANEJADO |
| LAC-INFRA-2 | infra+etl | P1 | Classificar `setor_grupo` (hoje tudo `A_CLASSIFICAR`) | V16 | VERIFICADO (Sessão 03, 2026-10-07): V21 classifica os 41 setores em 11 grupos, todos com 6 ou mais empresas (`MINIMO_GRUPO=5` do percentil), e define `regra_valuation` por grupo; validada sobre cópia dos dados, nenhum `A_CLASSIFICAR` restante. Agrupamento é proposta: revisar e corrigir com migration nova |
| LAC-INFRA-3 | infra | P1 | Script de backfill (DFP 2010–15, ITR 2011–23, COTAHIST 2009–15) | LAC-ETL-3/4 | PLANEJADO |
| LAC-INFRA-4 | infra+insights | P1 | Rotina mensal de cálculo de fatores/eventos (hoje `FATORES` e `EVENTOS_CORPORATIVOS` aparecem ATRASADA/SEM_DADO na saúde — esperado) | LAC-INS-9 | PLANEJADO |
| LAC-ETL-* | etl | P1 | Ver SPEC do ETL: proventos/COTAHIST/contas de qualidade entregues (f9832b0); TTM por trimestre e exercício fora do ano civil (c81278e); eventos corporativos, ITR 2011–2023 e backfill pendentes | — | EM ANDAMENTO (Sessão 03/feature-comunicados-cvm, 2026-10-07) |
| LAC-INS-* | insights | P1 | Entregues 1..9 (8e9e159); falta rodar contra dados reais após backfill | LAC-ETL | EM ANDAMENTO |
| LAC-GES-1..4 | gestor | P1 | Entregues (f548f97) | V16 | IMPLEMENTADO |
| LAC-FE-1..4 | painel | P1 | Placar por ranking, cartão Fatores, proventos DVA, saúde com novas fontes | LAC-GES | IMPLEMENTADO (2026-10-07, painel; falta reimplantar o gestor e validar com dados reais) |
| TASK-UX-5 | gestor | P2 | `GET` de listagem de ativos para o painel (favoritos + base): símbolo, empresa, setor, preço e variação, série curta para sparkline, sinal atual, último comunicado e flags de qualidade, paginado e filtrável por favorito/setor. Destrava a tabela única do painel (REQ-UX-8) | — | EM ANDAMENTO (Sessão 01/feature-teste, 2026-10-07) |
| TASK-UX-6 | painel | P2 | Tabela única de ativos no painel e remoção das listas redundantes (Base, Favoritos, Setores, Monitorados) | TASK-UX-5 | EM ANDAMENTO (Sessão 01/feature-comunicados-cvm, 2026-10-07) |
| TASK-E09 | etl | P2 | Agendar `--comunicados` (a rotina da manhã já o chama — confirmar e fechar) | — | VERIFICADO (Sessão 03, 2026-10-07): `scripts/cargas-etl.ps1` linha 28, passo `comunicados (IPE)` = `--comunicados`, primeiro da rotina |

A fila completa histórica (TASK-01..45, ISS-, INT-) continua nas seções 6–7 e nos SPECs dos serviços; esta tabela só lista o que está aberto **agora**.

### 1A.5 Contratos vigentes (índice; detalhe na seção 4)

CTR-01..15 (seção 4) + Plano LAC (V16): `provento_contabil` (escritor: ETL), `evento_corporativo` (ETL/insights), `setor_grupo`, `fator_definicao`/`fator_valor`/`fator_mercado_mensal` (insights), `backtest_ranking_*` (insights), `cotacao_b3_diaria` com colunas novas `especificacao`, `marca_ex`, `fator_cotacao`, `preco_medio`, ofertas (ETL). Leitores: gestor (somente leitura) → painel por HTTP. `etl_execucao` registra a última execução de cada fonte (usada por `/validacao/saude-dados`, que lista 13 fontes com prazo e criticidade).

### 1A.6 Decisões que não se desfazem sem discussão

Flyway é o único dono do schema; migration aplicada não se edita. Cada tabela tem um escritor. GET nunca grava/publica. BRAPI só para favoritos e dentro do orçamento. Preço oficial = COTAHIST; BRAPI é foto intradiária conciliada (`--conciliar`). Nenhum rótulo de recomendação sem aviso de regra experimental (Res. CVM 20/2021). Valor ausente é `NULL` com motivo, nunca 0. Dados de ponto-no-tempo (`data_entrega`) — sem look-ahead no backtest.

### 1A.7 Diário de handoff (mais novo no topo; uma linha por entrega)

| Data | Agente | Repo | O que mudou / o que fica pendente |
|---|---|---|---|
| 2026-10-07 | Claude (Sessão 03) | infra, etl | E19/E09 fechadas; E21: logs e backups em `%USERPROFILE%3-ecossistema` (os logs antigos ficam em AppData; dentro do app a cópia virtual esconde a real); E20: `registrar-rotinas.ps1` com `StartWhenAvailable` + logon +5 min — **o usuário roda:** `powershell -NoProfile -ExecutionPolicy Bypass -File scripts
egistrar-rotinas.ps1` fora do app. V17 corrigida (0b8b6ce) e V17–V20 aplicadas. Backup de 07-10 saiu 0x1 pela 2ª passada do ETL (ISS-E13) |
| 2026-10-04 | Claude (sessão infra/gestor) | todos | Refatoração dos 5 SPECs: seção 1A (hub) e blocos "Coordenação". Pendente: confirmar com o dono da sessão de contratos o commit dos arquivos soltos (T-INFRA-01); podar seções históricas |
| 2026-10-03 | Claude (sessão infra/gestor) | infra, gestor | V15/V16 aplicadas, Flyway reparado, LAC-GES-1..4, Frente A, restart policies; pushes feitos |
| 2026-09-30 | Sessões 01/03 | todos | Plano LAC proposto; ETL/insights LAC implementados; ver commits `f9832b0`, `8e9e159` |

## 2. Visão do sistema

Plataforma de acompanhamento de ações da B3 que coleta cotações, calcula valuation por regras (Graham) e produz uma análise textual com IA.

```text
B3/CVM -> ETL -> MySQL <- Gestor <- BRAPI
                        |   |
                        |   +-> SQS -> Worker -> MySQL
                        +-> API Gestor -> Painel
Infra/Flyway -> schema MySQL (único executor de migrations)
```

### 2.1 Fluxo ponta a ponta atual
1. GET consulta MySQL ou BRAPI sem escrita ou publicação, inclusive em cache vazio.
2. POST de cadastro persiste monitoramento e solicita coleta; o agendador mantém snapshots e séries.
3. Gestor publica eventos `schemaVersion=1.0`, com `dedupKey` estável; worker valida JSON Schema antes de abrir transação.
4. Worker reserva a chave na inbox `evento_processado` e grava o efeito na mesma transação. ACK só depois do commit; falha de processamento faz rollback; falha de ACK permite reentrega sem duplicação.
5. Gestor lê insights persistidos e consolida decisão determinística. Gemini e armazenamento S3 não fazem parte deste fluxo; recursos Terraform antigos podem permanecer provisionados.
6. ETL publica notificações versionadas de fundamentos e comunicados; ainda não há consumidores dessas filas. São notificações best-effort, não garantia de entrega transacional.

---

## 3. Topologia Docker

### 3.1 `docker-compose.yml` (imagens publicadas)

| Serviço | Imagem | Portas host | Depende de | Observações |
|---|---|---|---|---|
| localstack | `localstack/localstack:3.3` | 4566 | — | `SERVICES=sqs,s3,sns`, `DEBUG=1`, volume sem `PERSISTENCE` (estado efêmero) |
| my-terraform-provisioner | `ewertonmiranda/infra-b3-ecossystem:latest` | — | localstack healthy | `entrypoint` sobrescrito para `terraform init && apply` (ignora o `entrypoint.sh`, ver `ISS-06`) |
| mysql | `mysql:8.0` | 3305→3306 | — | Flyway cria e evolui o schema após healthcheck |
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

### 3.4 Schema MySQL (Flyway)
`mysql-migrations/` é a fonte exclusiva: V1 cria a base em banco vazio; bancos existentes mantêm baseline 1; V2–V10 conservam checksums; V11 adiciona inbox. `db-migrate` termina antes dos serviços. O mount mysql-init foi removido.

### 3.5 CI (`.github/workflows`)
- `01-feature-to-pr.yml`: abre PR `feature*` → `develop` automaticamente.
- `02-docker-build-push.yml`: em push para `develop` roda `terraform init -backend=false` + `validate` e publica `infra-b3-ecossystem` com as tags `develop`, `latest`, `sha` etc.
- O mesmo padrão existe nos dois serviços, **sem testes** antes da publicação.

---

## 4. Contratos entre serviços (fonte canônica)

| ID | Canal | Produtor → Consumidor | Formato / esquema | Garantias atuais |
|---|---|---|---|---|
| CTR-01 | SQS tratar-ativos | gestor → worker | `contracts/ativos.schema.json`, schemaVersion 1.0, dedupKey SHA-256 | Inbox transacional e índices únicos; compatibilidade com legado sem versão |
| CTR-02 | SQS sqs-registrar-series-historicas | gestor → worker | `contracts/series_historicas.schema.json`, schemaVersion 1.0; results preservado | Chave exclui requestedAt/took; inbox evita reaplicar reentrega; upsert por candle |
| CTR-03 | MySQL insight_acao | worker → gestor | `contracts/insight.schema.json`, schemaVersion e versao_payload 2.1; enum canônico gerado para Python, Java e JS | Leitura numérica de primeiro nível preservada; SEM_DADOS também versionado |
| CTR-04 | S3 (histórico, descontinuado) | — | Não integra o fluxo atual de análise | IMPLEMENTADO — retirada do uso pelo gestor; eventual recurso Terraform é legado |
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
| REQ-04 | Ter logs e métricas dos dois serviços centralizados | EM ANDAMENTO (`ISS-08`, `INT-06`) |
| REQ-05 | Ambiente de desenvolvimento com build local dos serviços | PLANEJADO (`ISS-04`) |

### 5.2 Não funcionais

| ID | Requisito | Status |
|---|---|---|
| NFR-01 | Nenhum segredo em arquivos do repositório ou no disco sem proteção | PLANEJADO (`ISS-01`) |
| NFR-02 | Versões de imagem fixadas (sem `latest`) para reprodutibilidade | PLANEJADO (`ISS-05`) |
| NFR-03 | Toda fila de trabalho com DLQ e `visibility_timeout` adequado | IMPLEMENTADO (2026-09-26) |
| NFR-04 | Idempotência ponta a ponta no fluxo consumido SQS | IMPLEMENTADO — inbox transacional V11, GET sem escrita e ACK após commit |
| NFR-05 | Schema com dono único e migrations versionadas | IMPLEMENTADO — V1 contém bootstrap; V2–V10 preservadas; V11 inbox; sem mysql-init |
| NFR-06 | O ecossistema sobe em máquina de 8 GB de RAM (perfil sem ELK opcional) | IMPLEMENTADO (`ISS-09`) |

---

## 6. Problemas identificados

### 6.1 Integração entre serviços (`INT-`)

| ID | Sev. | Problema | Evidência | Impacto | Correção sugerida | Status |
|---|---|---|---|---|---|---|
| INT-01 | Alto | Enum de recomendação não compartilhado: o gestor conta `"VENDA"`, o Python emite `"VENDA_VALUATION"` | `gestor: tools/ConsolidadorAnaliseAcao.java` × `gerar-insights: app/core/analysis/recommendation.py` | `perc_venda` sempre 0 no prompt do Gemini | Declarar o enum em CTR-03; testes de contrato nos dois lados | IMPLEMENTADO |
| INT-02 | Alto | Corrida: o gestor publica e lê `insight_acao` em seguida | `gestor: service/ServicoAtivo.java` | A análise de IA ignora o dado do dia; na primeira coleta não há análise | Evento "insight gerado" (usar o SNS `transmitir-lote-dados` ou uma fila `insight-gerado`) que dispara a análise | PLANEJADO |
| INT-03 | Alto | Nenhuma idempotência ponta a ponta: GET com efeito colateral + fila *at-least-once* + inserts sem chave natural | `gestor#ISS-09`, `gerar-insights#ISS-02` | `historico_acoes`/`insight_acao` duplicados distorcem a consolidação (sinal predominante contado N vezes) | `dedupKey = symbol + regularMarketTime` como atributo da mensagem + `UNIQUE` no banco | IMPLEMENTADO |
| INT-04 | Alto | Três donos de schema: `mysql-init` (infra), Hibernate `ddl-auto=update` (gestor), entidades SQLAlchemy (Python) | `mysql-migrations/V1__baseline.sql`, `gestor application-*.properties` | Drift; o Hibernate pode alterar a tabela `insight_acao` do Python | Dono único: migrations versionadas (Flyway ou Alembic) em um lugar; gestor com `validate`; `mysql-init` só para bootstrap | IMPLEMENTADO |
| INT-05 | Médio | O gestor depende de campos de primeiro nível de `detalhes_json` que a spec do Python classificava como "legado" | `gestor: ConsolidadorAnaliseAcao.consolidarIndicadores` | Removê-los no Python quebra a análise de IA sem erro visível | Formalizados em CTR-03; `gerar-insights` não pode removê-los sem nova versão | PLANEJADO |
| INT-06 | Médio | Observabilidade assimétrica: Python sem `/metrics` e com logs só em stdout (fora do ELK); Java loga em texto num arquivo lido como JSON **e** via TCP (duplicado) | `prometheus.yml`, `logstash.conf`, `gestor logback-spring.xml` | Target `gerar-insights` sempre *down*; logs duplicados ou quebrados no Kibana | Python: `prometheus_client` em :8080 + logs JSON; Java: JSON só via TCP; remover o input de arquivo **ou** padronizar arquivos JSON | PLANEJADO |
| INT-07 | Médio | Timestamp da cotação perdido no contrato (`regularMarketTime`) | `gestor#ISS-07` | Impossível deduplicar por pregão ou ordenar corretamente | ISO-8601 UTC obrigatório em CTR-01 | PLANEJADO |
| INT-08 | Baixo | Recursos provisionados sem uso: `sqs-iniciar-treinamento`, SNS `transmitir-lote-dados` | `infra/main.tf` | Ruído/confusão | Documentar o uso planejado (DEC-03) ou remover | PLANEJADO |

### 6.2 Infraestrutura e Docker (`ISS-`)

| ID | Sev. | Problema | Evidência | Impacto | Correção sugerida | Status |
|---|---|---|---|---|---|---|
| ISS-01 | **Crítico** | Chaves reais BRAPI/Gemini em texto puro | `docker-compose-local.yml` (não versionado, mas sem proteção no `.gitignore`); também em `gestor/src/main/resources/application-test.properties` | Vazamento no primeiro `git add .` | Revogar e gerar novas chaves; mover para `.env` (listado no `.gitignore`) com `env_file`; adicionar `docker-compose-local.yml`/`.env` ao `.gitignore` ou usar só `${VAR}`; gitleaks no CI | PLANEJADO |
| ISS-02 | Alto | Filas sem DLQ e sem `visibility_timeout`/`redrive_policy` | Módulo cria uma DLQ por fila, `maxReceiveCount=5`, retenção de 14 dias e visibilidade de 120 s | Mensagem venenosa é isolada | Validar no LocalStack após apply | IMPLEMENTADO (2026-09-26) |
| ISS-03 | Alto | `mysql-init` só roda com volume vazio | Compose executa Flyway one-shot com migrations versionadas e o gestor valida o schema | Bancos existentes recebem as colunas e índices novos | Migração V2 é idempotente | IMPLEMENTADO (2026-09-26) |
| ISS-04 | Alto | `docker-compose-local.yml` aponta para contextos de build inexistentes (`./gestor-ativos-brutos`, `./gerar-insights`) | `docker-compose-local.yml` | Ambiente de desenvolvimento local não sobe | `context: ../gestor-ativos-brutos/gestor-ativos-brutos` e `../gerar-insights/gerar-insights`, ou variável `ECOSYSTEM_ROOT`; usar `docker-compose.override.yml` para builds locais | PLANEJADO |
| ISS-05 | Médio | Imagens `latest` (serviços, prometheus, grafana, terraform) e tag `latest` publicada a partir de `develop` | `docker-compose.yml`, workflows | Build não reproduzível; `develop` quebrado vira `latest` | Fixar versões/digests; `latest` só a partir de tag semver em `main` | PLANEJADO |
| ISS-06 | Médio | O compose sobrescreve o `entrypoint.sh` do provisionador, pulando `validate`/`plan` e os logs estruturados | `docker-compose.yml` (`entrypoint: terraform init && apply`) | Perde as validações que a imagem oferece | Remover o override e usar o `ENTRYPOINT` da imagem | PLANEJADO |
| ISS-07 | Médio | Credenciais e flags inseguras: Grafana `admin/admin`, Elasticsearch sem segurança, LocalStack `DEBUG=1`, MySQL `root/root`, todas as portas expostas no host | `docker-compose.yml` | Aceitável só em máquina local; perigoso se reaproveitado em servidor | Variáveis em `.env`; bind em `127.0.0.1:`; marcar o compose como "somente dev" | PLANEJADO |
| ISS-08 | Médio | `gerar-insights` expõe 8080 e o Prometheus faz scrape dele, mas o worker não tem HTTP | `docker-compose.yml`, `prometheus.yml` | Target sempre *down*; porta enganosa | Implementar `/metrics` e `/health` no worker (INT-06) ou remover porta e job | PLANEJADO |
| ISS-09 | Médio | Pilha pesada: ES + Logstash + Kibana + Prometheus + Grafana + 2 JVMs (≈ 3–4 GB RAM) sempre ligados | `docker-compose.yml` | Máquina de desenvolvimento lenta | Compose `profiles` (`core`, `observability`); `docker compose --profile observability up` quando necessário | PLANEJADO |
| ISS-10 | Baixo | `CreatedAt = timestamp()` nas tags causa diff permanente | `infra/locals.tf` | `plan` nunca fica limpo | Remover a tag ou usar `lifecycle { ignore_changes = [tags["CreatedAt"]] }` | PLANEJADO |
| ISS-11 | Baixo | Healthcheck do MySQL no compose local sem credenciais; `gestor` espera só `service_started` | `docker-compose-local.yml` | Java pode subir antes do banco estar pronto | Mesmo healthcheck do compose principal + `service_healthy` | PLANEJADO |
| ISS-12 | Baixo | CI da infra publica imagem sem `terraform fmt -check`, tflint ou checkov | `.github/workflows/02-docker-build-push.yml` | Qualidade e segurança do IaC não verificadas | Adicionar fmt/tflint/checkov | PLANEJADO |
| ISS-13 | Médio | Trabalho registrado no código nos **três** repositórios, em branches `feature-*` diferentes | `git status` de cada repo | Mudanças de contrato (série histórica, nova fila e tabela) podem ser integradas fora de ordem | Ordem de merge: infra (fila e tabela) → gerar-insights (consumidor) → gestor (produtor) | PLANEJADO |

---

## 7. Roadmap do ecossistema

### Fase 0 — Segurança e ambiente que sobe (bloqueante)

| ID | Tarefa | Resolve | Repos | Critério de aceite | Status |
|---|---|---|---|---|---|
| TASK-01 | Revogar e gerar novas chaves BRAPI/Gemini; `.env` + `.env.example`; gitleaks nos 3 CIs | ISS-01, NFR-01 | infra, gestor | Nenhum segredo em `git grep`; pipeline bloqueia segredo | PLANEJADO |
| TASK-25 | Série histórica longa via COTAHIST da B3, quebrando o teto de 3 meses da BRAPI | CTR-05 | infra, etl | Carga filtra ativos monitorados, divide preços por 100 e grava `fonte='B3'` | IMPLEMENTADO (2026-09-26) |
| TASK-26 | Decidir e implementar o ajuste por proventos da série do COTAHIST (a fonte entrega preço bruto) | TASK-20 | etl | Fonte estruturada oficial identificada no UP2DATA, sem contrato gratuito confirmado; série permanece bruta e explicitamente sinalizada | BLOQUEADO por fonte/licença |
| TASK-27 | Registrar em CTR-05 o segundo escritor de `serie_historica` (B3 além de BRAPI) e a regra de precedência | TASK-20 | infra | CTR-05 nomeia os dois escritores e diz qual vence na mesma chave | IMPLEMENTADO (2026-09-26) |
| TASK-02 | Corrigir os contextos de build do compose local e usar o mesmo healthcheck | ISS-04, ISS-11 | infra | `docker compose -f docker-compose-local.yml up --build` sobe tudo *healthy* | PLANEJADO |
| TASK-03 | Serviço one-shot `db-migrate` (Flyway) que aplica o schema de forma idempotente | ISS-03, INT-04 | infra | Com volume antigo, colunas e índices novos existem após `up` | IMPLEMENTADO (2026-09-26) |
| TASK-04 | Merge coordenado das features pendentes na ordem infra → gerar-insights → gestor | ISS-13 | todos | Os 3 repos com `git status` limpo e PRs mergeados em `develop` | PLANEJADO |

### Fase 1 — Contratos e confiabilidade

| ID | Tarefa | Resolve | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|---|
| TASK-10 | DLQ + `visibility_timeout` + retenção no módulo SQS | ISS-02, NFR-03 | infra, gerar-insights | Mensagem que falha 5× vai para `<fila>-dlq` | — | IMPLEMENTADO (2026-09-26) |
| TASK-11 | Enum de recomendações + `schemaVersion` + JSON Schema dos payloads em `contracts/` neste repo | INT-01, INT-05, CTR-01..03 | todos | Testes de contrato nos dois serviços validam contra `contracts/*.schema.json` | — | IMPLEMENTADO |
| TASK-12 | Idempotência ponta a ponta (`dedupKey`, `UNIQUE`, GET sem efeito colateral) | INT-03, INT-07, NFR-04 | todos | Reenviar a mesma mensagem 3× gera 1 linha | TASK-11 | IMPLEMENTADO |
| TASK-13 | Dono único de schema com migrations; gestor em `ddl-auto=validate` | INT-04, NFR-05 | todos | DEC-01 registrada; startup falha se houver drift | DEC-01 | IMPLEMENTADO |
| TASK-14 | Evento "insight gerado" desacoplando a análise de IA | INT-02 | todos | Análise S3 criada **depois** do insight do dia | DEC-02 | PLANEJADO |

### Fase 2 — Operação

| ID | Tarefa | Resolve | Critério de aceite | Status |
|---|---|---|---|---|
| TASK-20 | Compose `profiles` (core / observability) e bind em 127.0.0.1 | ISS-07, ISS-09 | `docker compose up` sem profile sobe só o core | PLANEJADO |
| TASK-21 | Observabilidade uniforme: métricas e logs JSON do Python; logs do Java sem duplicação; dashboards Grafana provisionados | INT-06, ISS-08 | Os 2 targets *up* no Prometheus; 1 evento = 1 documento no ES | PLANEJADO |
| TASK-22 | Fixar versões de imagem; `latest` só em release | ISS-05 | Nenhum `:latest` no compose | PLANEJADO |
| TASK-23 | Usar o `entrypoint.sh` do provisionador; remover `timestamp()` das tags; fmt/tflint/checkov no CI | ISS-06, ISS-10, ISS-12 | `terraform plan` limpo na 2ª execução | PLANEJADO |
| TASK-24 | Decidir e implementar/remover `sqs-iniciar-treinamento` e SNS | INT-08 | DEC-03 registrada | PLANEJADO |

### Fase 3 — Precisão e confiabilidade (plano de 2026-09-27)

Ponto de partida medido: dados 31/31 com preço, balanço, data de entrega e TTM; regra oficial v1 `2026.09.27-2` com compras raras e com vantagem ainda não significativa (teste, 63 pregões: 24 janelas, 58% contra taxa-base de 52%), vendas sem vantagem e fração de vendas dependente do regime de juros (`gerar-insights#DEC-07`). Ordem sugerida: TASK-43 e TASK-30 → TASK-31 (+ TASK-39, TASK-40 em paralelo) → TASK-34, 35, 37, 38 → TASK-32, 33, 41, 42, 44.

**Onda 1 — medir melhor (precisão estatística)**

| ID | Tarefa | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|
| TASK-30 | Intervalo de confiança em todo placar: Wilson 95% para o acerto, média ± 1,96·erro-padrão para o excesso; "acima/abaixo da base" só quando o intervalo não cruza a taxa-base | gerar-insights, gestor, painel, infra (V9) | Painel mostra "58% (46–69%)"; linha sem significância aparece como "indistinguível da base" | — | IMPLEMENTADO (2026-09-27): V9, `tools/IntervaloConfianca` (gestor), `agregar` com desvio (gerar-insights), leitura no painel. Supõe janelas independentes — ver TASK-31 |
| TASK-31 | Universo de backtest amplo e sem viés de sobrevivência: ações de lote padrão com ≥ 200 pregões e liquidez mínima **no ano anterior**, incluindo deslistadas, a partir do COTAHIST e dos DFP em cache; régua de mercado = média desse universo | etl, infra, gerar-insights | ≥ 3× janelas; deslistadas incluídas; intervalo de confiança por bootstrap em blocos (janelas sobrepostas e ativos correlacionados deixam o intervalo de TASK-30 otimista); cobertura de CNPJ por ano exibida; backtest < 5 min | TASK-30, **gerar-insights#TASK-59** | CONCLUIDO (2026-09-27): COTAHIST amplo 2016-2026 (1.785 códigos, 1,16 mi pregões); universo point-in-time em `app/validacao/universo.py` (≥ 200 pregões e ≥ R$ 5 mi/dia no ano anterior, sem units nem BDRs, com deslistadas): 93 a 191 ações por ano; DFP 2016-2025 de 249 empresas (`etl --universo-backtest`); backtest com 258 ativos, 15.732 amostras (5×); IC por bootstrap em blocos de meses (V12, `bootstrap.py`). **Resultado: nenhuma regra com vantagem distinguível** — acerto e excesso cruzam a base em todas as linhas, exceto a compra moderada da v1 antiga (+1,1% s/ carteira, IC +0,3 a +2,0). 38 papéis sem balanço por troca de código: `infra#TASK-45` |
| TASK-32 | Sinais técnicos (momentum, reversão à média) avaliados no backtest como regras próprias | gerar-insights | Placar próprio; entram na recomendação só com vantagem nos dois períodos (DEC) | TASK-31 | PLANEJADO |
| TASK-33 | Curva de calibração do score de confiança (acerto real por faixa de score) | gerar-insights, gestor, painel | Gráfico no painel; DEC: recalibrar ou retirar o score | TASK-31 | PLANEJADO |

**Onda 2 — corrigir a regra (precisão do modelo)**

| ID | Tarefa | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|
| TASK-34 | Crescimento nominal na v1 (g real + IPCA 12m) contra Y real (Selic − IPCA), escolhido por backtest | gerar-insights | Fração de vendas varia < 10 p.p. entre calibração e teste; separação não piora; DEC | TASK-31 | IMPLEMENTADO (2026-09-27): G_NOMINAL adotado (`gerar-insights#DEC-08`); vendas 20% → 32% entre calibração e teste (11,6 p.p., aceite era < 10) |
| TASK-35 | `VENDA_VALUATION` vira `SEM_MARGEM` (sem direção) enquanto não houver vantagem medida com IC | gerar-insights, gestor, painel | Contrato de recomendações versionado (INT-01); tela sem "venda" generalizada | TASK-30 | PLANEJADO |
| TASK-36 | Proventos: retorno e régua com proventos (feito: `gerar-insights` 7ea0d1e, 13b6287); contagem `janelas_com_provento` no placar (V10, `gerar-insights#TASK-56`); falta o histórico além dos ~12 meses que a B3 devolve por consulta (`gerar-insights#TASK-46`) | gestor, gerar-insights | Placar diz quantas janelas foram ajustadas; histórico com fonte registrada em DEC | — | EM ANDAMENTO |
| TASK-37 | Recalibrar limiares no universo amplo, objetivo pelo limite inferior do IC | gerar-insights | DEC com limiares e intervalo | TASK-31, TASK-34 | CONCLUIDO (2026-09-27), sem mudança de limiares — ver `gerar-insights#DEC-09`: nenhuma das 1.944 combinações válidas teve o limite inferior do IC da separação acima de zero na calibração (melhor: −2,1 a +3,2 p.p.) |
| TASK-38 | Decidir v1 × v2 pelos números (a vencedora nos dois períodos, com IC, vira a oficial) | gerar-insights | DEC com números; `VERSAO_REGRA` incrementada | TASK-37 | PLANEJADO |

**Onda 3 — confiabilidade operacional**

| ID | Tarefa | Repos | Critério de aceite | Depende de | Status |
|---|---|---|---|---|---|
| TASK-39 | Checagens de dados depois de cada carga (lucro zero com receita, LPA fora da mediana, balanço sem data de entrega, salto sem evento, papel sem CNPJ, BRAPI × COTAHIST) gravadas em `checagem_dados`; severidade ERRO vira ERRO na saúde dos dados | etl, infra (migração nova), gestor | O caso TIMS3 (lucro 0) é pego sozinho; teste de regressão | — | PLANEJADO |
| TASK-40 | Alerta ativo: `checar-saude.ps1` diário lê `/validacao/saude-dados` e avisa por Telegram no estado PROBLEMA; grava `saude_dados_historico` | infra, gestor | Falha provocada chega ao celular (bot criado pelo usuário) | — | PLANEJADO |
| TASK-41 | Backup fora da máquina (pasta sincronizada ou disco externo), semanal, com restauração mensal testada a partir da cópia | infra | Restauração da cópia registrada na saúde dos dados | — | PLANEJADO |
| TASK-42 | CI com teste, lint e tipos antes do build nos 5 repositórios; corrigir o teste `>Formulas<` do painel | todos | Pipeline vermelho bloqueia a imagem | — | PLANEJADO |
| TASK-43 | Protocolo de trabalho paralelo entre sessões/agentes (regra 6 da seção 1) | infra | Regra escrita; nenhum commit misturado depois dela | — | IMPLEMENTADO (2026-09-27) |
| TASK-44 | Sequência de dias com a saúde dos dados verde, na aba Avaliação | gestor, painel | Evidência para a nota de confiabilidade 7 | TASK-40 | PLANEJADO |
| TASK-45 | Curadoria de códigos renomeados do universo amplo na `ativo_identidade` (VIIA3→BHIA3, KROT3→COGN3, BTOW3/AMER3, SUZB5→SUZB3, VALE5, RUMO3→RAIL3, CLSA3, DMMO3…): 38 dos 258 papéis do backtest ficaram sem balanço porque o FCA não liga o código antigo ao CNPJ | etl, infra (migração nova) | Lista de "sem nenhum balanço" nas observações do backtest cai para perto de zero | TASK-31 | ABERTO |

---

## 8. Decisões

| ID | Pergunta | Opções | Recomendação da análise | Status |
|---|---|---|---|---|
| DEC-01 | Dono do schema MySQL | Infraestrutura/Flyway, diretório mysql-migrations | Java apenas validate; Python apenas DML; não editar migrations aplicadas | IMPLEMENTADO |
| DEC-02 | Gatilho da análise de IA | síncrono / evento SNS pós-insight / agendamento | Evento pós-insight | PLANEJADO |
| DEC-03 | Destino de `sqs-iniciar-treinamento` e do SNS `transmitir-lote-dados` | manter com caso de uso documentado / remover | Usar o SNS no DEC-02; remover a fila de treinamento até existir consumidor | PLANEJADO |
| DEC-04 | Fonte dos contratos | infra/contracts/*.schema.json | Distribuição pelo script sincronizar-contratos.mjs; --check detecta divergências | IMPLEMENTADO |
| DEC-05 | Ambiente alvo além do local | só local / AWS real (dev/homolog/prod já previstos em `var.environment`) | Definir antes de TASK-13 do gestor (credenciais) | PLANEJADO |

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

## Revisão integrada de 2026-09-27

| Entrega | Estado | Evidência e limite |
|---|---|---|
| Proprietário único do schema | IMPLEMENTADO | Infra/Flyway: V1 bootstrap, V11 inbox; serviços não executam migrations |
| Eventos e recomendações | IMPLEMENTADO | schemas canônicos em infra/contracts; enum gerado em Java, Python e JS; versões desconhecidas ficam para DLQ |
| Leituras HTTP e idempotência | IMPLEMENTADO | GET sem persistência/publicação; inbox e efeitos na mesma transação; ACK posterior ao commit |
| Verificação desta entrega | EM ANDAMENTO | Resultados registrados em infra/VERIFICACAO-2026-09-27.md; não representa deploy no banco em uso |

## Plano LAC: 9 lacunas de assertividade (proposta de 30-09-2026, EM AVALIAÇÃO)

**Objetivo.** O backtest da regra atual (execução 14) não mostra vantagem no período de teste: todo intervalo de confiança de acerto contém a taxa-base. Antes de trocar a regra, a base de dados precisa ficar justa (proventos, desdobramentos, lucro trimestral, mais anos) e a avaliação precisa ter poder estatístico (ranking entre ações). Este plano cobre as 9 lacunas com **uma única migração (V16)** e só com **COTAHIST e CVM** como fonte.

### Fontes: só COTAHIST e CVM (verificado em 30-09-2026)

| # | Lacuna | Fonte | Situação hoje | Limite honesto |
|---|---|---|---|---|
| L1 | Histórico de proventos | CVM DFP/ITR, demonstração **DVA** (7.08.04.01 JCP, 7.08.04.02 Dividendos) + **marcas ex do COTAHIST** (ED, EJ, EDJ…) | Já no cache (`dfp_cia_aberta_DVA_*`); ETL não lê nenhum dos dois | Valor **por período** (DVA); a data ex vem do COTAHIST (481 EJ e 253 ED no BDI 02 em 2026). O valor de cada evento é o total do trimestre repartido entre as datas ex dele: aproximação |
| L2 | Desdobramentos e grupamentos | **Marca ex no ESPECI do COTAHIST** (EB, EG, EX…) para a data + composição de capital (DFP/ITR) para a proporção | Dados já existem; o leitor ignora o ESPECI | A data vem do COTAHIST, sem heurística (achado da Sessão 01, conferido em 30-09-2026: 22 EB e 24 EG no BDI 02 em 2026). A proporção ainda é calculada; o significado exato de cada marca deve ser conferido no layout oficial da B3 |
| L3 | Balanço trimestral histórico | CVM ITR desde 2011 | Cache tem 2024–2026 | Precisa baixar 2011–2023 (mesmo pipeline) |
| L4 | Mais anos | COTAHIST desde 2009; CVM DFP desde 2010 | Cache tem 2016+ | CVM aberta começa em 2010: sinais só a partir de 2011 |
| L5 | Fatores de preço | COTAHIST | Pronto | — |
| L6 | Qualidade e endividamento | CVM DFP/ITR (BPA, BPP, DRE, DFC) | Parcial | Faltam 4 contas no ETL (ativo total, ativo e passivo circulante, lucro bruto) |
| L7 | Comparação no setor | CVM FCA (`cvm_empresa.setor`, 41 setores) | Pronto | 15 empresas sem setor; agrupamento precisa de revisão humana |
| L8 | Eventos de comunicados | CVM IPE (`comunicado_cvm`, 4.139) | Pronto | Só metadados (categoria, datas), não o texto; 36 datas de referência inválidas: usar `data_entrega` |
| L9 | Fatores de referência | **Construídos** com COTAHIST + CVM (MKT, SMB, HML, WML, IML, QMJ) | — | Substitui o NEFIN/USP (fonte externa). Menos auditado que o NEFIN |

Nenhuma lacuna exige fonte paga ou fora de COTAHIST/CVM.

### Modelo relacional

```
cvm_empresa (cnpj) ──< fato_contabil (+coluna_df)          [L1 DVA/DMPL, L3, L4, L6]
      │          ──< provento_contabil                       [L1: JCP+dividendos por período]
      │          ──< cvm_composicao_capital ─┐
      │          ──< comunicado_cvm (+índice)│               [L8]
      │                                      ▼
      └─ setor ── setor_grupo           evento_corporativo   [L2: inferido de capital × preço]
                   (grupo, regra)             │
cotacao_b3_diaria (simbolo, data) ────────────┘ ajuste de preço na leitura
      │
      ├──> fator_valor (simbolo, data_ref, fator) >── fator_definicao   [L5, L6, L7, L8]
      └──> fator_mercado_mensal (data_ref, fator)                       [L9]

backtest_execucao (+metodo, esquema, hipotese, tentativa)
      ├──< backtest_placar            (método CLASSES, já existe)
      └──< backtest_ranking_mes ──< backtest_ranking_quintil  (método RANKING)
```

Decisões do modelo:
- **Formato longo para fatores** (`fator_valor` + `fator_definicao`): fator novo é uma linha no catálogo, não uma migração. É o que mantém a V16 como migração única.
- **Dado bruto num lugar só:** DVA e DMPL entram no `fato_contabil`, que já guarda BPA/BPP/DRE/DFC. `provento_contabil` e `evento_corporativo` são derivados e reprocessáveis.
- **Ponto no tempo em toda tabela nova:** `data_entrega` (DT_RECEB da CVM) em proventos; fatores calculados no primeiro pregão do mês só com o que era público até ali.
- **Ajuste de desdobramento na leitura**, não gravando uma cópia ajustada do COTAHIST: o preço bruto oficial continua intacto e auditável.

### Migração única V16 (validada em banco temporário em 30-09-2026)

Rodada contra cópias vazias das tabelas alteradas: sem erro; 41 setores e 16 fatores semeados; colunas geradas conferidas (desdobramento 2:1 → `fator_preco` 0,5; WEG 2024: JCP + dividendos = R$ 3,19 bi).

```sql
-- V16__lacunas_assertividade.sql
-- L1 e L6: DVA e DMPL no fato_contabil (DMPL tem a coluna do patrimonio).
ALTER TABLE fato_contabil
    ADD COLUMN coluna_df VARCHAR(60) NOT NULL DEFAULT '' AFTER cd_conta,
    DROP INDEX uq_fato_contabil,
    ADD UNIQUE KEY uq_fato_contabil
        (cnpj, tipo_doc, grupo, demonstracao, dt_fim_exerc, dt_ini_exerc, cd_conta, coluna_df);

-- L1: proventos por periodo (DVA). DFP = ano; ITR = trimestre isolado.
CREATE TABLE provento_contabil (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    cnpj                VARCHAR(20)       NOT NULL,
    tipo_doc            VARCHAR(5)        NOT NULL,
    dt_ini_exerc        DATE              NOT NULL,
    dt_fim_exerc        DATE              NOT NULL,
    versao              SMALLINT UNSIGNED NOT NULL,
    data_entrega        DATE              NULL,
    jcp                 DECIMAL(24,2)     NULL,
    dividendos          DECIMAL(24,2)     NULL,
    total               DECIMAL(24,2) GENERATED ALWAYS AS (COALESCE(jcp, 0) + COALESCE(dividendos, 0)) STORED,
    acoes_ex_tesouraria BIGINT            NULL,
    por_acao            DECIMAL(18,8)     NULL,
    origem              VARCHAR(20)       NOT NULL DEFAULT 'CVM_DVA',
    cobertura_json      JSON              NULL,
    criado_em           DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_provento_contabil (cnpj, tipo_doc, dt_fim_exerc),
    KEY idx_provento_contabil_entrega (cnpj, data_entrega),
    CONSTRAINT chk_provento_contabil_tipo_doc CHECK (tipo_doc IN ('DFP', 'ITR'))
);

-- L2: desdobramento, grupamento e bonificacao (inferidos).
CREATE TABLE evento_corporativo (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    simbolo        VARCHAR(12)    NOT NULL,
    cnpj           VARCHAR(20)    NULL,
    data_efeito    DATE           NOT NULL,
    tipo           VARCHAR(20)    NOT NULL,
    fator_acoes    DECIMAL(20,10) NOT NULL,
    fator_preco    DECIMAL(20,10) GENERATED ALWAYS AS (1 / fator_acoes) STORED,
    origem         VARCHAR(30)    NOT NULL,
    confianca      DECIMAL(5,4)   NULL,
    evidencia_json JSON           NULL,
    criado_em      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_evento_corporativo (simbolo, data_efeito, tipo),
    KEY idx_evento_corporativo_cnpj (cnpj, data_efeito),
    CONSTRAINT chk_evento_corporativo_tipo CHECK (tipo IN ('DESDOBRAMENTO', 'GRUPAMENTO', 'BONIFICACAO')),
    CONSTRAINT chk_evento_corporativo_fator CHECK (fator_acoes > 0),
    CONSTRAINT chk_evento_corporativo_origem CHECK (origem IN ('INFERIDO_CVM_COTAHIST', 'MANUAL'))
);

-- L3/L4: sem tabela nova (fato_contabil, indicador_fundamentalista,
-- cvm_composicao_capital e cotacao_b3_diaria so crescem).

-- L6: contas para qualidade (liquidez, margem bruta, Piotroski).
ALTER TABLE indicador_fundamentalista
    ADD COLUMN ativo_total        DECIMAL(24,2) NULL AFTER patrimonio_liquido,
    ADD COLUMN ativo_circulante   DECIMAL(24,2) NULL AFTER ativo_total,
    ADD COLUMN passivo_circulante DECIMAL(24,2) NULL AFTER ativo_circulante,
    ADD COLUMN lucro_bruto        DECIMAL(24,2) NULL AFTER receita_liquida;

-- L7: agrupamento de setores e regra de valuation por grupo.
CREATE TABLE setor_grupo (
    setor_cvm       VARCHAR(60) PRIMARY KEY,
    grupo_setor     VARCHAR(40) NOT NULL,
    regra_valuation VARCHAR(20) NOT NULL DEFAULT 'GRAHAM',
    observacao      VARCHAR(300) NULL,
    CONSTRAINT chk_setor_grupo_regra CHECK (regra_valuation IN ('GRAHAM', 'PL_SETOR', 'PVP_SETOR', 'DIVIDENDOS'))
);
INSERT INTO setor_grupo (setor_cvm, grupo_setor)
SELECT DISTINCT setor, 'A_CLASSIFICAR' FROM cvm_empresa WHERE setor IS NOT NULL;

-- L5, L6, L8: fatores em formato longo.
CREATE TABLE fator_definicao (
    codigo            VARCHAR(40)  PRIMARY KEY,
    familia           VARCHAR(20)  NOT NULL,
    descricao         VARCHAR(300) NOT NULL,
    fonte             VARCHAR(20)  NOT NULL,
    direcao_esperada  TINYINT      NOT NULL,
    defasagem_pregoes SMALLINT     NOT NULL DEFAULT 0,
    versao_calculo    VARCHAR(20)  NOT NULL,
    ativo             BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_fator_definicao_familia CHECK (familia IN ('PRECO', 'QUALIDADE', 'VALOR', 'EVENTO')),
    CONSTRAINT chk_fator_definicao_fonte CHECK (fonte IN ('COTAHIST', 'CVM_DFP_ITR', 'CVM_IPE', 'COTAHIST_CVM')),
    CONSTRAINT chk_fator_definicao_direcao CHECK (direcao_esperada IN (-1, 0, 1))
);

CREATE TABLE fator_valor (
    simbolo            VARCHAR(12)    NOT NULL,
    data_referencia    DATE           NOT NULL,
    fator_codigo       VARCHAR(40)    NOT NULL,
    valor              DECIMAL(24,10) NULL,
    percentil_universo DECIMAL(7,4)   NULL,
    percentil_setor    DECIMAL(7,4)   NULL,
    grupo_setor        VARCHAR(40)    NULL,
    calculado_em       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (simbolo, data_referencia, fator_codigo),
    KEY idx_fator_valor_data (data_referencia, fator_codigo),
    CONSTRAINT fk_fator_valor_definicao FOREIGN KEY (fator_codigo) REFERENCES fator_definicao (codigo)
);

INSERT INTO fator_definicao (codigo, familia, descricao, fonte, direcao_esperada, defasagem_pregoes, versao_calculo) VALUES
    ('MOMENTO_12_1',          'PRECO',     'Retorno de 12 meses excluindo o ultimo mes', 'COTAHIST', 1, 21, '1'),
    ('VOLATILIDADE_12M',      'PRECO',     'Desvio-padrao anualizado dos retornos diarios em 12 meses', 'COTAHIST', -1, 0, '1'),
    ('LIQUIDEZ_63D',          'PRECO',     'Volume financeiro medio diario em 63 pregoes', 'COTAHIST', 1, 0, '1'),
    ('BETA_12M',              'PRECO',     'Beta contra a media do universo em 12 meses', 'COTAHIST', -1, 0, '1'),
    ('DRAWDOWN_12M',          'PRECO',     'Queda do pico em 12 meses', 'COTAHIST', 1, 0, '1'),
    ('ROIC',                  'QUALIDADE', 'EBIT sobre capital investido (PL + divida liquida)', 'CVM_DFP_ITR', 1, 0, '1'),
    ('ALAVANCAGEM',           'QUALIDADE', 'Divida liquida sobre patrimonio liquido', 'CVM_DFP_ITR', -1, 0, '1'),
    ('MARGEM_BRUTA',          'QUALIDADE', 'Lucro bruto sobre receita liquida', 'CVM_DFP_ITR', 1, 0, '1'),
    ('ACCRUALS',              'QUALIDADE', '(Lucro liquido - fluxo de caixa operacional) sobre ativo total', 'CVM_DFP_ITR', -1, 0, '1'),
    ('PIOTROSKI',             'QUALIDADE', 'Escore F de Piotroski (0 a 9)', 'CVM_DFP_ITR', 1, 0, '1'),
    ('CRESCIMENTO_LPA',       'QUALIDADE', 'Variacao do LPA dos ultimos 12 meses contra 12 meses antes', 'CVM_DFP_ITR', 1, 0, '1'),
    ('EARNINGS_YIELD',        'VALOR',     'LPA dos ultimos 12 meses sobre preco', 'COTAHIST_CVM', 1, 0, '1'),
    ('BOOK_TO_MARKET',        'VALOR',     'VPA sobre preco', 'COTAHIST_CVM', 1, 0, '1'),
    ('DIVIDEND_YIELD',        'VALOR',     'Proventos por acao em 12 meses (DVA) sobre preco', 'COTAHIST_CVM', 1, 0, '1'),
    ('FATOS_RELEVANTES_90D',  'EVENTO',    'Fatos relevantes entregues nos ultimos 90 dias', 'CVM_IPE', 0, 0, '1'),
    ('AVISOS_PROVENTOS_180D', 'EVENTO',    'Avisos de proventos entregues nos ultimos 180 dias', 'CVM_IPE', 1, 0, '1');

-- L8: contagem de comunicados por empresa e janela de entrega.
ALTER TABLE comunicado_cvm
    ADD KEY idx_comunicado_evento (cnpj, categoria, data_entrega);

-- L9: fatores de referencia construidos (no lugar do NEFIN).
CREATE TABLE fator_mercado_mensal (
    data_referencia DATE          NOT NULL,
    fator_codigo    VARCHAR(10)   NOT NULL,
    versao_calculo  VARCHAR(20)   NOT NULL,
    retorno         DECIMAL(14,8) NOT NULL,
    n_ativos_long   INT           NULL,
    n_ativos_short  INT           NULL,
    calculado_em    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (data_referencia, fator_codigo, versao_calculo),
    CONSTRAINT chk_fator_mercado_codigo CHECK (fator_codigo IN ('MKT', 'SMB', 'HML', 'WML', 'IML', 'QMJ'))
);

-- Metodo: ranking, janelas sucessivas e registro de tentativas.
ALTER TABLE backtest_execucao
    ADD COLUMN metodo            VARCHAR(20) NOT NULL DEFAULT 'CLASSES' AFTER status,
    ADD COLUMN esquema_validacao VARCHAR(20) NOT NULL DEFAULT 'CORTE_UNICO' AFTER metodo,
    ADD COLUMN hipotese          TEXT        NULL AFTER esquema_validacao,
    ADD COLUMN numero_tentativa  INT         NULL AFTER hipotese,
    ADD CONSTRAINT chk_backtest_execucao_metodo CHECK (metodo IN ('CLASSES', 'RANKING')),
    ADD CONSTRAINT chk_backtest_execucao_esquema CHECK (esquema_validacao IN ('CORTE_UNICO', 'JANELAS_SUCESSIVAS'));

CREATE TABLE backtest_ranking_mes (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    execucao_id     BIGINT       NOT NULL,
    versao_regra    VARCHAR(20)  NOT NULL,
    janela          VARCHAR(20)  NOT NULL,
    data_referencia DATE         NOT NULL,
    horizonte       SMALLINT     NOT NULL,
    ic_spearman     DECIMAL(8,6) NULL,
    n_ativos        INT          NOT NULL,
    UNIQUE KEY uq_backtest_ranking_mes (execucao_id, versao_regra, janela, data_referencia, horizonte),
    CONSTRAINT fk_backtest_ranking_mes_execucao FOREIGN KEY (execucao_id) REFERENCES backtest_execucao (id) ON DELETE CASCADE
);

CREATE TABLE backtest_ranking_quintil (
    ranking_mes_id BIGINT        NOT NULL,
    quintil        TINYINT       NOT NULL,
    retorno_medio  DECIMAL(12,6) NULL,
    n_ativos       INT           NOT NULL,
    PRIMARY KEY (ranking_mes_id, quintil),
    CONSTRAINT fk_backtest_ranking_quintil_mes FOREIGN KEY (ranking_mes_id) REFERENCES backtest_ranking_mes (id) ON DELETE CASCADE,
    CONSTRAINT chk_backtest_ranking_quintil CHECK (quintil BETWEEN 1 AND 5)
);

-- L1, L2 e L5: campos do COTAHIST que o leitor ignora hoje (achados da
-- Sessao 01, conferidos em 30-09-2026). marca_ex = sufixo do ESPECI no dia
-- ex (EJ, ED, EB, EG, ES...); fator_cotacao = FATCOT (AZUL53 1.000.000,
-- GOLL54 1.000: preco gravado hoje multiplicado); preco_medio = PREMED
-- (VWAP); melhores ofertas no fechamento = PREOFC/PREOFV (spread real).
ALTER TABLE cotacao_b3_diaria
    ADD COLUMN especificacao        VARCHAR(10)   NULL AFTER simbolo,
    ADD COLUMN marca_ex             VARCHAR(4)    NULL AFTER especificacao,
    ADD COLUMN fator_cotacao        INT           NOT NULL DEFAULT 1 AFTER marca_ex,
    ADD COLUMN preco_medio          DECIMAL(14,4) NULL AFTER fechamento,
    ADD COLUMN melhor_oferta_compra DECIMAL(14,4) NULL AFTER preco_medio,
    ADD COLUMN melhor_oferta_venda  DECIMAL(14,4) NULL AFTER melhor_oferta_compra,
    ADD KEY idx_cotacao_b3_marca_ex (marca_ex, data_pregao);
```

Este último bloco também foi validado em banco temporário (30-09-2026). Os ~1,16 mi de linhas atuais ficam com as colunas novas nulas até a recarga do COTAHIST, que já está prevista no backfill.

### Carga histórica (uma vez, fora da rotina diária)

| Carga | Volume estimado | Comando |
|---|---|---|
| COTAHIST 2009–2015 | ~1,3 mi linhas em `cotacao_b3_diaria`, ~90 MB por ano de download | `etl --cotahist --ano 2009 ... --ano 2015` |
| DFP 2010–2015 (com DVA, DMPL, composição) | ~0,4 mi linhas em `fato_contabil` | `etl --ano 2010 ... --ano 2015 --universo-backtest` |
| ITR 2011–2023 | ~2 mi linhas em `fato_contabil` | `etl --ttm --ano 2011 ... --ano 2023` e a nova carga trimestral (ETL, LAC-ETL-3) |
| Reprocessar DFP/ITR 2016–2026 com DVA e DMPL | reaproveita o cache (sem download) | `etl --ano ... --forcar` |
| Reprocessar COTAHIST 2016–2026 com ESPECI, FATCOT, PREMED e ofertas | reaproveita o cache (sem download) | `etl --cotahist --ano ... --forcar` |

Volume final estimado do banco: de ~1,7 GB para ~3,5 GB. O backup diário cresce na mesma proporção.

### Tarefas desta aplicação

| ID | Tarefa | Depende de |
|---|---|---|
| LAC-INFRA-1 | Criar `mysql-migrations/V16__lacunas_assertividade.sql` com o DDL acima; `flyway validate` limpo | Aprovação deste plano |
| LAC-INFRA-2 | Revisar o agrupamento dos 41 setores (`setor_grupo`) e a regra de valuation de cada grupo; o resultado entra na própria V16, no lugar de `A_CLASSIFICAR` | LAC-INFRA-1 |
| LAC-INFRA-3 | Script `scripts/backfill-historico.ps1`, idempotente, com a ordem da tabela acima e registro em `etl_execucao` | LAC-ETL-1..3 |
| LAC-INFRA-4 | Rotina da manhã: etapa mensal (1º dia útil) de cálculo de fatores e de fatores de mercado, depois do COTAHIST | LAC-INS-5..8 |
| LAC-INFRA-5 | Revisar o tamanho do backup e a retenção (de ~45 MB para ~90 MB por dia) | LAC-INFRA-3 |

### Divisão entre aplicações

| Aplicação | Lacunas | Seção |
|---|---|---|
| infra-b3-ecossytem | V16, backfill, rotina | esta |
| etl-fundamentos-cvm | L1, L2, L3, L4, L6 (contas), L8 (datas) | `etl-fundamentos-cvm/SPEC.md`, Plano LAC |
| gerar-insights | L1/L2 no retorno, L5, L6, L7, L8, L9, método de ranking | `gerar-insights/SPEC.md`, Plano LAC |
| gestor-ativos-brutos | Leitura do novo placar e dos fatores | `gestor-ativos-brutos/SPEC.md`, Plano LAC |
| painel-ativos-frontend | Exibição do placar por ranking e dos fatores na ficha | `painel-ativos-frontend/SPEC.md`, Plano LAC |

### Aceite do plano inteiro

1. Backtest refeito com proventos (DVA) e desdobramentos ajustados, de 2011 a 2026, com o **método de ranking em janelas sucessivas**.
2. Cada fator novo aparece no placar como versão de regra própria, com `hipotese` registrada **antes** da execução e `numero_tentativa` preenchido.
3. Uma regra só é promovida se o intervalo de 95% da correlação de ranking (ou da diferença entre quintis) ficar acima de zero nas janelas de teste **e** o diário ao vivo não contradisser.

### Riscos

| Risco | Mitigação |
|---|---|
| Proventos da DVA por período, não por evento | Tratar como fluxo trimestral a partir de `data_entrega`; medir o efeito comparando com os 12 meses de `provento_distribuido` (evento) já existentes |
| Desdobramento com proporção errada | A data vem da marca ex do COTAHIST; a proporção da composição de capital precisa bater com o salto de preço. `confianca` e `evidencia_json` por evento; abaixo do limiar, fica fora do ajuste e a janela é descartada como hoje |
| Significado de marca do ESPECI assumido errado | Conferir o layout oficial do COTAHIST da B3 antes de codificar; conjunto de eventos conhecidos como teste |
| Mais testes, mais chance de achar sorte | `hipotese` e `numero_tentativa` obrigatórios; exigência maior para a melhor de N tentativas; diário ao vivo como juiz final |
| V16 altera a chave única de `fato_contabil` (~0,5 mi linhas) | Rodar com a stack parada; backup antes; tempo estimado de 1–2 min |
