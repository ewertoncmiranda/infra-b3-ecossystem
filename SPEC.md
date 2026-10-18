# SPEC — Hub de coordenação do ecossistema B3

Este documento coordena mudanças que atravessam os repositórios `etl-fundamentos-cvm`, `gestor-ativos-brutos`, `gerar-insights`, `painel-ativos-frontend` e esta infraestrutura. Os SPECs de cada aplicação detalham as tarefas locais. A infraestrutura é a única proprietária das migrações Flyway e dos contratos físicos compartilhados.

## Plano OPDB/CARTDB — opções confiáveis e Carteiras persistentes (2026-10-17)

### Objetivo e limites

Tornar os dados de opções rastreáveis até a fonte, coerentes entre ETL, banco, API e tela, e evoluir Carteiras compartilhadas na instância para persistir operações com quantidade/preço, proventos recebidos e retorno histórico. O sistema registra operações informadas pelo usuário; não executa ordens nem representa custódia de corretora.

### Opções: contrato e qualidade

- Fonte do tipo call/put: o tipo de mercado do registro de origem, mapeado uma vez para `CALL`/`PUT`; código BDI é campo diferente e não substitui tipo.
- Armazenar/servir data do pregão da cotação e status de validade. Tipo desconhecido não deve ser convertido silenciosamente; linha inválida é rejeitada/isolada com motivo observável.
- A tabela corrente contém apenas linhas aceitas pelo contrato e pela constraint. Preservar trilha de carga e contagens de rejeição sem tornar registros inválidos negociáveis.
- API e UI deixam claros coleção vazia, dado desatualizado e falha de serviço. Estratégias/insights permanecem bloqueados até a cadeia passar pelo gate de qualidade `OPT-INS-1`.
- A reconstrução de dados deve ocorrer pela rotina única já existente do ETL; não criar comando, flag, script avulso ou backfill manual novo.

### Carteiras: modelo lógico e semântica

Carteiras são compartilhadas na instância (single-user operacional), sem autenticação, entidade de dono ou isolamento por usuário. `carteira.nome` é apenas um rótulo descritivo. V42 guarda metadados e alocação simulada; não guarda quantidade comprada, preço de execução, proventos recebidos nem retorno. V43 acrescenta ledger de operações, recebimentos e snapshots versionados. `capital_alocado` legado não pode ser convertido em compra nem em quantidade inferida.

Capital alocado em V42 é anotação/simulação, não quantidade comprada. Em V43, preço de execução e quantidade são persistidos no ledger de operações; preço de mercado continua vindo de fonte oficial com data/origem, e retorno é persistido como snapshot derivado/versionado, nunca como entrada manual. Não migrar nem apagar `localStorage` até importação confirmada pelo servidor; repetição deve ser idempotente.

### Tarefas da infraestrutura

| ID | Tarefa | Escopo | Dependências | Aceite | Status |
|---|---|---|---|---|---|
| OPDB-INFRA-1 | Compatibilizar persistência de opções | `mysql-migrations/V41__contrato_opcao_b3.sql`: permitir status emitido pelo ETL (`VALIDA`/`INVALIDA`), manter estados legados apenas para leitura, e ajustar views para contar inválidos sem reclassificá-los | Contrato documentado abaixo | Migração aditiva, sem revalidar/promover linhas antigas; `tipo_opcao` e `bdi` permanecem campos distintos; consumidores filtram operacionalidade por `VALIDA` | APLICADO E VERIFICADO NO BANCO LOCAL (2026-10-18, schema v41) |
| CARTDB-INFRA-1 | Criar schema persistente para Carteiras | `mysql-migrations/V42__carteiras_persistentes.sql`: tabelas `carteira` e `carteira_ativo`, FK com cascade, IDs compatíveis com o store atual e ticker único por carteira | Contrato documentado abaixo | Capital positivo em `DECIMAL`; alocação identificada como simulada; remoção de carteira não deixa ativo órfão; schema não alega isolamento multiusuário | APLICADO E VERIFICADO NO BANCO LOCAL (2026-10-18, schema v42) |
| CARTDB-INFRA-2 | Evoluir schema para Carteiras compartilhadas, operações, proventos e retorno | `mysql-migrations/V43__carteiras_operacoes_proventos_retorno.sql`; V42 é imutável | V42 e contrato abaixo | Migração aditiva: não altera nem apaga carteiras/alocações legadas; compras/vendas guardam quantidade, preço, custos, impostos e fluxo assinado; recebimentos deduplicáveis; snapshots guardam fonte/data/método/versão | IMPLEMENTADA; MySQL 8 descartável validou DDL, idempotência, estorno e proteção de histórico; Flyway/upgrade no banco integrado pendente (2026-10-18) |

### Contrato canônico: opções

`opcao_b3_diaria` mantém os nomes físicos atuais para não quebrar o produtor/consumidor:

| Campo | Significado e regra canônica |
|---|---|
| `simbolo` | Símbolo completo do instrumento derivativo na B3; não é o ativo-objeto. |
| `ativo_objeto` | Ticker do ativo subjacente reconhecido pelo parser; pode ser nulo em registro não operacional. |
| `tipo_opcao` | `CALL` ou `PUT`, inferido pelo tipo de mercado COTAHIST (`TPMERC` 070 ou 080). É o único campo usado para nomear tipo no domínio/API. |
| `bdi` | Código `CODBDI` original (ex. `12`, `14`), preservado como classificação de origem. Não usar para derivar nem sobrescrever `tipo_opcao`. |
| `status_validacao` | Novas escritas do ETL usam somente `VALIDA` ou `INVALIDA`. `REJEITADA`, `INCOMPLETA` e `LEGADO_NAO_VALIDADO` são estados históricos mantidos por compatibilidade e não devem ser emitidos pelo novo parser. Somente `VALIDA` é operacional/negociável para leitura. |
| `motivo_rejeicao` | Texto estruturado produzido pelo ETL (até 80 caracteres); consumidores tratam como código opaco e não alteram sua capitalização. Nulo para opção válida. |
| `data_pregao` | Pregão ao qual os preços se referem; não confundir com data de carga nem data atual. |

V41 não altera nem apaga dados existentes e não promove status. As views de qualidade contam `INVALIDA` junto a `REJEITADA`; o gestor filtra `status_validacao = 'VALIDA'`, devolve o `tipo_opcao` persistido e pode expor o `bdi` original separadamente. O ETL continua sendo o único escritor desta tabela. `tipo_opcao` e os campos de validação foram criados em V30; V41 fecha a compatibilidade e não muda sua semântica.

### Contrato canônico: Carteiras

Carteiras pertencem à instância compartilhada; não existe usuário/dono no modelo e não se deve criar ou inferir essa entidade. A propriedade operacional é apenas do deployment. O campo `nome` é descritivo, não chave de identidade nem mecanismo de autorização. Não há garantia de isolamento entre clientes ou usuários.

#### Compatibilidade legada V42

O contrato físico existente (V42, imutável) é:

| Tabela/campo | Tipo/regra |
|---|---|
| `carteira.id` | `VARCHAR(64)` PK. Mantém compatibilidade com IDs string `c_...` já gerados por `b3-carteiras`. |
| `carteira.nome` | `VARCHAR(120)` obrigatório. |
| `carteira.estrategia` | `VARCHAR(80)` obrigatório; texto aberto para preservar valores existentes e permitir evolução. |
| `carteira.cor` | `VARCHAR(7)` obrigatório, `#RGB` ou `#RRGGBB`. |
| `carteira.moeda_base` | `CHAR(3)`, padrão `BRL`. |
| `carteira.status` | `ATIVA` ou `ARQUIVADA`, padrão `ATIVA`. |
| `carteira.criada_em` / `atualizada_em` | `DATETIME` com criação e atualização automáticas. |
| `carteira_ativo.carteira_id` | `VARCHAR(64)` FK para `carteira.id`, `ON DELETE CASCADE`. |
| `carteira_ativo.simbolo` | `VARCHAR(12)`; PK composta (`carteira_id`, `simbolo`), logo há um registro ativo por ticker/carteira no MVP. |
| `carteira_ativo.data_entrada` | `DATE`, mapeia `dataEntrada` no store atual. |
| `carteira_ativo.capital_alocado` | `DECIMAL(18,2)` positivo, mapeia `capital`; é capital de alocação simulada, não execução. |

V42 mapeia o JSON legado (`id`, `nome`, `estrategia`, `cor`, `criadaEm`, `ativos: [{ simbolo, dataEntrada, capital }]`). `capital_alocado` significa somente alocação simulada. V43 não reclassifica nem remove esse dado; os registros antigos permanecem disponíveis, sem gerar operações ou quantidade implícitas.

#### Novas tabelas V43

| Tabela | Contrato físico e semântica |
|---|---|
| `carteira_operacao` | Ledger de registros informados pelo usuário. `id` UUID; FK `carteira_id`; `tipo` COMPRA/VENDA/APORTE/RETIRADA/TAXA/IMPOSTO/ESTORNO; `simbolo`, `quantidade DECIMAL(24,8)` e `preco_unitario DECIMAL(20,8)` obrigatórios em compra/venda; valor bruto, custos, impostos e valor líquido assinado; moeda, origem e `chave_idempotencia` única por carteira. Compra debita caixa (líquido negativo); venda/aporte creditam (positivo); retirada/taxa/imposto debitam (negativo). ESTORNO referencia operação anterior da mesma carteira; a API valida inversão exata. APP não executa ordens nem atesta transações de corretora. Ledger é append-only, sem exclusão ou edição; após haver histórico financeiro, carteira é arquivada, não apagada. |
| `carteira_provento_recebido` | Um recebimento confirmado pelo usuário, nunca um anúncio: ativo, tipo DIVIDENDO/JCP/RENDIMENTO/AMORTIZACAO/OUTRO, datas ex/pagamento, quantidade elegível e valor unitário opcionais, bruto, imposto retido, líquido, moeda, referência externa e chave idempotente por carteira. |
| `carteira_ativo_valuation_diaria` | Quantidade calculada do ledger, preço de fechamento, data do pregão efetivamente usada, fonte (padrão `COTAHIST_B3`), valor de mercado e `versao_calculo`; PK inclui carteira, ativo, data de referência e versão. Captura o insumo usado sem substituir `cotacao_b3_diaria`. |
| `carteira_rentabilidade_diaria` | Valor de mercado, caixa, fluxo externo, proventos líquidos, resultado realizado/não realizado, retorno do período e acumulado (fração decimal nullable), método TWR ou INDISPONIVEL, versão e hora de cálculo. PK inclui carteira, data de referência e versão. Null indica que retorno não pôde ser calculado. |

Todas as tabelas V43 têm FK restritiva para preservar o histórico ao impedir hard-delete de carteira com dados financeiros, e são compartilhadas na instância, sem coluna ou chave de usuário. O serviço não deve apresentar essa estrutura como multiusuário, custódia de corretora ou execução de ordens. As chaves idempotentes tornam reenvios seguros; operação e recebimento são separados porque um evento anunciado não prova o recebimento. Preços oficiais continuam no domínio de mercado (`cotacao_b3_diaria`); snapshots preservam preço/data/fonte efetivamente consumidos. Retorno é dado derivado e versionado, não valor editável no cliente. Ativos legados sem operações não têm quantidade/valor de mercado calculáveis e devem permanecer fora do retorno até uma operação real ser registrada; não converter capital alocado em posição. `provento_contabil` de DFP/ITR é dado contábil por ação, não evento de distribuição nem comprovante de recebimento.

Importação do `localStorage` deve ser idempotente, manter cópia local até confirmação e preservar alocações antigas como legado; nunca inferir compras, quantidades, preços, proventos ou retorno a partir de `capital_alocado`.

### Plano de execução sem colisões entre agentes

Regra operacional: no máximo um agente altera cada repositório por vez; toda tarefa tem um dono explícito, branch/worktree próprio quando aplicável, e lista de arquivos autorizados. Nenhum agente edita SPECs durante ondas de implementação; o coordenador mantém este hub e atualiza status em uma janela exclusiva de documentação. Não dividir simultaneamente um arquivo ou contrato compartilhado.

| Onda | Dono exclusivo | Trabalho | Bloqueio/saída |
|---|---|---|---|
| 0 — contrato | Coordenador, sem outros agentes implementando | Instância compartilhada sem dono/usuário; congelar semântica de ledger/recebimento/retorno; V42 continua legado | Contrato congelado |
| 1 — banco | Um agente Infra | Implementar OPDB-INFRA-1 e CARTDB-INFRA-1/2, testar banco novo e upgrade; somente este agente edita migrations/compose | V41/V42 aplicadas; validar V43 em banco descartável/clone antes de aplicar no ambiente integrado |
| 2A — extração | Um agente ETL | OPDB-ETL-1..3 no repositório ETL; usar tipo de mercado, validação, observabilidade e reconstrução automática no start único | Contrato de banco da onda 1 integrado |
| 2B — insights | Um agente Insights, em paralelo a 2A em repositório distinto | OPDB-INS-1: preservar/testar gate; não incluir Carteiras nem estratégias antes da qualidade | Gate testado; sem escrita em ETL/Infra |
| 3 — API | Um agente Gestor, após V43 | OPDB-GES-1; depois CARTDB-GES-1..6: CRUD compartilhado, operações, recebimentos, avaliação e histórico; sem autenticação/isolamento por usuário | API e semântica estáveis antes da tela |
| 4 — interface | Um agente Frontend, após 3 | OPDB-PAI-1; então CARTDB-PAI-1..7 em sequência | Não concorrer com OPT-PAI-3/OPCX-PAI-3 nem dividir arquivos compartilhados |
| 5 — integração | Coordenador único | Testes de contrato e fluxo ponta a ponta, atualizar status dos SPECs e registrar débitos/decisões | Aceite integrado abaixo; nenhum agente altera código durante a rodada de integração |

Ondas 2A e 2B podem ocorrer simultaneamente porque têm repositórios e arquivos exclusivos. Qualquer outra paralelização requer fronteiras de arquivos sem sobreposição e contratos previamente congelados. Se ETL e gestor precisarem de ajuste conjunto, o coordenador serializa as alterações: fecha ETL/contrato primeiro, depois gestor. Commits por repositório permanecem separados; não fazer cherry-pick de alterações de outro agente sem revisão do proprietário.

### Aceite integrado

1. Um registro válido de cada tipo percorre fonte → ETL → banco → API → UI com CALL/PUT correto e data de pregão identificável.
2. Registro desconhecido, rejeitado, vencido, cadeia vazia e erro de serviço são distinguíveis; nenhum estado inválido é apresentado como opção negociável.
3. Gate de insights impede consumo de opções sem qualidade suficiente e não afeta estratégias independentes.
4. Criar/editar/remover Carteira e ativos, registrar operações e recebimentos e ler snapshots persiste após recarga na instância compartilhada; reenvios são idempotentes. Registros V42 permanecem inalterados e não geram operações implícitas.
5. Retorno só aparece com fonte/data disponíveis, inclui método e versão e distingue valores calculados de informações declaradas; não representa custódia/execução confirmada. A interface/documentação não promete isolamento ou acesso privado por usuário.
6. Migrações, testes automatizados dos quatro repositórios e fluxo de inicialização único da stack passam; nenhum novo comando manual foi introduzido.

### Índice de escopo por aplicação

- ETL: `etl-fundamentos-cvm/SPEC.md` — OPDB-ETL-1..3 e CARTDB-ETL-1 (somente eventos corporativos aprovados; nunca estado de usuário).
- Insights: `gerar-insights/SPEC.md` — OPDB-INS-1.
- Gestor/API: `gestor-ativos-brutos/SPEC.md` — OPDB-GES-1, CARTDB-GES-1..6.
- Frontend: `painel-ativos-frontend/SPEC.md` — OPDB-PAI-1, CARTDB-PAI-1..7.
- Infra/schema e coordenação: este documento — OPDB-INFRA-1, CARTDB-INFRA-1..2.
