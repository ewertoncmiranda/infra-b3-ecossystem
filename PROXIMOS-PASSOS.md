# Próximos passos — documento de passagem

**Escrito em:** 2026-09-26
**Para:** quem continuar o trabalho (humano ou outro modelo), sem acesso à conversa que originou isto.

> **Atualização de execução — 2026-09-26:** foram implementados a ingestão COTAHIST/B3, o cálculo TTM com ITR, a atomicidade e idempotência do worker, a contagem da família `VENDA_*`, DLQs, Flyway e o ajuste de fixação da tela de velas. A série COTAHIST permanece bruta: o ajuste por eventos corporativos aguarda definição de uma fonte estruturada/licenciada. Credenciais locais não fazem parte deste conjunto de commits.

Este documento é autossuficiente de propósito. Leia as seções 1 e 2 antes de escrever qualquer linha de código — a seção 2 contém decisões que são fáceis de desfazer sem perceber.

---

## 1. Onde o ecossistema está hoje

Cinco repositórios, todos com árvore limpa e tudo enviado:

| Repositório | Caminho local | Branch | Papel |
|---|---|---|---|
| `painel-ativos-frontend` | `C:\Users\User\projetos\painel-ativos-frontend` | `main` | Front (Web Components, Bootstrap CDN, sem bundler) |
| `gestor-ativos-brutos` | `...\gestor-ativos-brutos\gestor-ativos-brutos` (aninhado) | `feature-teste` | API Java/Spring, única que fala com a BRAPI |
| `gerar-insights` | `...\gerar-insights\gerar-insights` (aninhado) | `feature-migrate` | Worker Python, consome SQS |
| `etl-fundamentos-cvm` | `C:\Users\User\projetos\etl-fundamentos-cvm` | `main` | Job em lote, dados abertos da CVM |
| `infra-b3-ecossytem` | `C:\Users\User\projetos\infra-b3-ecossytem` | `feature-nova-infra` | Compose, Terraform, schema, glossário |

Repare que dois repositórios têm o código numa pasta aninhada de mesmo nome.

### Subir o ambiente

```bash
cd C:\Users\User\projetos\infra-b3-ecossytem
docker compose -f docker-compose-local.yml up -d          # faz build do código local
docker compose -f docker-compose-local.yml --profile etl run --rm etl-fundamentos-cvm
```

O front fica em `http://localhost:8082`, a API em `:8091`, o MySQL em `:3305`.

### O que foi concluído recentemente

- ETL dos fundamentos da CVM, em arquitetura hexagonal, gravando `indicador_fundamentalista`
- Rota `GET /analises/{simbolo}/fundamentos-cvm` com P/L e P/VP derivados na leitura
- Front: aba Glossário (97 verbetes), aba Padrões e armadilhas, detecção de padrões sobre o gráfico
- Correção do preço ajustado no cálculo técnico do `gerar-insights`

---

## 2. Decisões que NÃO devem ser desfeitas sem discussão

Estas são o núcleo intelectual do trabalho. São fáceis de destruir por engano, porque à primeira vista parecem excesso de zelo.

### 2.1 Taxa de acerto nunca aparece sozinha

Em `painel-ativos-frontend/public/js/analise/taxaAcerto.js`.

Toda taxa de acerto de um padrão é exibida **ao lado da taxa-base da janela** — o percentual de vezes que o preço foi na direção esperada considerando *todos* os candles, não só os do padrão. O número que informa é a diferença entre as duas.

Motivo: se o ativo subiu em 55% dos pregões, um padrão de alta com 58% de acerto está empatado com escolher um dia ao acaso. Mostrar só "58%" é enganoso.

Medido na carteira real (7 ativos, 448 candles, horizonte de 3 pregões): o **engolfo de alta acertou 33,3% contra uma base de 53,7%** — vinte pontos *abaixo* do acaso.

### 2.2 Sem percentual abaixo de 5 ocorrências

`AMOSTRA_MINIMA = 5`. Abaixo disso, a interface mostra a contagem crua ("2 acertos em 3 ocorrências"), nunca um percentual. Transformar 2/3 em "66,7%" dá a esses casos uma precisão que eles não têm.

### 2.3 Janelas disjuntas

Tanto a taxa-base quanto as ocorrências do padrão usam janelas que não se sobrepõem. Duas ocorrências a menos de H pregões uma da outra compartilham o mesmo futuro; contá-las duas vezes é contar o mesmo resultado duas vezes.

### 2.4 Calibragem no ruído

Cada padrão em `detectorPadroes.js` carrega `ruidoPorJanela`: quantas vezes ele dispara, em média, numa série **aleatória** do mesmo tamanho. Os valores vêm de `npm test`.

O número que justifica tudo isso: em ruído puro, a estrela da manhã exibiu **+12,1 pontos de vantagem** sobre a taxa-base. Por isso o limite para o painel chamar algo de "acima da base" é exigente (15 pontos). Se mexer nos detectores, **rode `npm test` e atualize os valores de `ruidoPorJanela`**.

### 2.5 Padrões que não são detectados, e por quê

OCO, topo duplo, triângulos e bandeiras estão em `PADROES_NAO_DETECTAVEIS` com a razão exibida na interface. Não é falta de esforço: são figuras cuja definição depende de tolerâncias arbitrárias, e automatizá-las produz um detector que dispara em ruído. **Não implemente sem antes medir quanto o detector novo dispara numa série aleatória.**

### 2.6 Métrica ausente é declarada, nunca estimada

No ETL da CVM, quando o plano de contas da companhia não comporta a métrica (margem e ROIC de banco, por exemplo), o valor é `NULL` **de propósito** e a razão vai em `cobertura_json`. Ausência explícita é melhor que número errado.

### 2.7 Preço ajustado por proventos

Dividendo e desdobramento derrubam o preço sem ninguém vender. O ajuste é aplicado às **quatro pontas** da vela (fator `adjustedClose / close`), não só ao fechamento — ajustar só o close faz o valor cair fora do intervalo mínima–máxima e a vela vira um desenho impossível.

---

## 3. Tarefa principal: série histórica longa via COTAHIST da B3

### O problema

O plano gratuito da BRAPI limita o histórico a **3 meses** (~63 pregões). Isso trava três coisas:

- Médias de 200 períodos e *golden cross* são impossíveis
- Formações longas (OCO leva 3 a 6 meses) não cabem na janela
- A validação estatística de padrões fica sem amostra: mesmo somando a carteira inteira chega-se a ~450 candles

### A fonte, já verificada

O COTAHIST da B3 é gratuito, oficial e tem série desde 1986.

```
Anual:  https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A2025.ZIP   (~89 MB)
Diário: https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_D25092026.ZIP (~0,6 MB)
```

Ambos verificados respondendo HTTP 200 em 2026-09-26. Dentro do ZIP há um único `.TXT` de largura fixa, encoding **latin-1**, linhas de 245 caracteres.

### Layout do registro de cotação (TIPREG = `01`)

Posições em base 1, conforme o arquivo real. **Preços têm 2 decimais implícitas** (divida por 100):

| Campo | Posição | Exemplo (PETR4, 25/09/2026) |
|---|---|---|
| TIPREG | 1–2 | `01` |
| DATA | 3–10 | `20260925` |
| CODBDI | 11–12 | `02` |
| CODNEG (ticker) | 13–24 | `PETR4       ` |
| TPMERC | 25–27 | `010` = lote padrão |
| NOMRES | 28–39 | `PETROBRAS   ` |
| ESPECI | 40–49 | `PN      N2` |
| PREABE (abertura) | 57–69 | `0000000004880` → 48,80 |
| PREMAX (máxima) | 70–82 | `0000000004887` → 48,87 |
| PREMIN (mínima) | 83–95 | `0000000004792` → 47,92 |
| PREMED (média) | 96–108 | `0000000004822` → 48,22 |
| PREULT (fechamento) | 109–121 | `0000000004799` → 47,99 |
| TOTNEG (nº negócios) | 148–152 | `39788` |
| QUATOT (quantidade) | 153–170 | `34440400` |
| VOLTOT (volume R$) | 171–188 | → 1.660.839.773,00 |
| CODISI | 231–242 | `BRPETRACNPR6` |

Filtre `TIPREG == '01'` e `TPMERC == '010'` (lote padrão) para ações à vista. `CODBDI == '02'` também é lote padrão; outros códigos são fracionário, opções, etc.

Conferido contra o painel: os cinco preços do PETR4 batem exatamente com o que a BRAPI entrega.

### ⚠️ O problema que precisa ser resolvido antes, não depois

**O COTAHIST não tem preço ajustado.** Verifiquei o registro inteiro: os campos restantes são PREEXE, INDOPC, DATVEN, FATCOT, PTOEXE, CODISI e DISMES. O `FATCOT` é *fator de cotação* (tamanho do lote), **não** ajuste por provento.

Ou seja: carregar 10 anos de COTAHIST e rodar os detectores em cima **reintroduz exatamente a armadilha corrigida em 2026-09-26**, e de forma muito pior — em 10 anos o PETR4 acumula dezenas de proventos, e a série bruta fica cheia de degraus artificiais que o detector lerá como gaps e reversões.

Três caminhos, em ordem de qualidade:

1. **Carregar também os eventos corporativos da B3 e calcular o fator de ajuste.** É o correto e é trabalho real: precisa de dividendos, JCP, bonificações, desdobramentos e grupamentos, com data *ex*, e do cálculo cumulativo retroativo do fator. Sem isso a série longa não serve para análise de padrão.
2. **Carregar o COTAHIST bruto e marcar claramente a série como não ajustada**, usando-a apenas para volume, liquidez e número de negócios — métricas insensíveis a degrau de preço. Entrega valor rápido sem enganar.
3. Ignorar o problema. **Não faça isso.** Produziria uma validação estatística de aparência rigorosa e resultado sem significado.

Recomendo começar pelo caminho 2 e evoluir para o 1. Registre a escolha como um `DEC-` na spec.

Já registrado em `infra-b3-ecossytem/SPEC.md`: **TASK-25** (a carga), **TASK-26** (o ajuste por proventos) e **TASK-27** (o segundo escritor em `CTR-05`).

### Onde o código deve morar

Recomendação: **dentro de `etl-fundamentos-cvm`**, como um segundo caso de uso. A arquitetura já tem tudo o que é preciso — cache em volume, verificação de ETag, unidade de trabalho, repositórios com upsert — e criar um sexto repositório para um adaptador só é sobrecarga.

Há uma tensão de nome: o repositório se chama "etl-fundamentos-cvm" e passaria a carregar também dados de mercado da B3. Duas saídas: aceitar e ajustar a descrição para "ETL de dados abertos", ou criar repositório novo. **É decisão do dono do projeto** — registre como `DEC-` (a numeracao de TASK no SPEC vai ate TASK-27; a de DEC ate DEC-01 neste repo).

Estrutura sugerida, seguindo o que já existe:

```
app/adaptadores/b3/
  cliente_http_b3.py      # HEAD/ETag + GET, espelhando ClienteHttpCvm
  leitor_cotahist.py      # ZIP + parsing de largura fixa, latin-1
  fonte_b3.py             # implementa uma porta nova, FonteDeSeries
app/portas/fonte_series.py
app/aplicacao/carregar_series_historicas.py
tests/adaptadores/test_leitor_cotahist.py
```

O parser é a peça que mais merece teste: largura fixa não perdoa deslocamento de uma posição, e o erro é silencioso.

### Destino no banco

A tabela `serie_historica` já existe, com chave natural `(simbolo, data_pregao, intervalo)` e coluna `fonte`.

**Atenção ao conflito de escritores.** Hoje quem escreve nela é o `gerar-insights`, com `fonte = 'BRAPI'` (contrato `infra#CTR-05`). Um segundo escritor com `fonte = 'B3'` colide na mesma chave única.

Decisão necessária: a B3 é a bolsa, então o dado dela é autoritativo e deve sobrescrever o da BRAPI no mesmo dia. Se concordar, faça upsert com `fonte = 'B3'` e **atualize `infra#CTR-05` para registrar os dois escritores** — pelo protocolo da spec, mudança de contrato exige isso.

### Volume de dados

Um ano de COTAHIST tem ~16.600 linhas por dia útil no arquivo diário; o anual chega a 89 MB comprimido. Carregue **apenas os tickers de `ativo_monitorado`**, como o ETL da CVM já faz — é o mesmo princípio e reduz a carga em três ordens de grandeza.

### Critérios de aceite (Dado/Quando/Então, como as specs pedem)

- Dado o COTAHIST anual de 2025; Quando a carga rodar para WEGE3; Então `serie_historica` recebe ~250 candles com `fonte = 'B3'`, e abertura/máxima/mínima/fechamento batem com o arquivo dividido por 100.
- Dado que a carga já rodou; Quando rodar de novo com o mesmo ETag; Então nada é baixado e `etl_execucao` registra `PULADO`.
- Dado um ticker que não está em `ativo_monitorado`; Quando a carga rodar; Então ele não é gravado.
- Dado que a série é bruta; Quando for exibida ou analisada; Então a origem não ajustada é sinalizada ao usuário.

### Depois disso, o que se destrava

Com série longa, refaça a validação estatística de padrões com amostra de verdade. Hoje ela roda sobre 448 candles; com 10 anos de 8 ativos seriam ~20.000. Aí os números da seção 2.1 passam a ter peso — e é bem possível que a conclusão mude.

---

## 4. Backlog, com contexto

Em ordem aproximada de valor.

### 4.1 TTM a partir do ITR — `etl-fundamentos-cvm#ISS-E01`

**O maior débito do ETL.** Hoje só há exercício fechado (DFP anual). As referências de mercado publicam 12 meses móveis, e a diferença passa de 40% em empresa de lucro volátil — medido: VALE3 variou −56% de 2024 para 2025.

Enquanto não existir, o Graham do `gerar-insights` **não deve** consumir o LPA da CVM. A rota nova é read-only para o usuário de propósito.

Cuidado técnico: o DRE do ITR é **acumulado no ano**. O trimestre isolado sai por subtração usando `DT_INI_EXERC`. É onde mora o bug sutil.

### 4.2 Testes Java nunca foram executados

`gestor-ativos-brutos` tem testes novos (`ServicoFundamentosCvmTest`, `CalculadoraMultiplosTest`) que **compilam mas nunca rodaram**: o Maven não baixa o provider do surefire neste ambiente por erro de certificado TLS. Rode `mvn test` numa máquina com rede normal antes de confiar neles. As asserções de `BigDecimal` com escala exata são as mais suspeitas.

Observação de ambiente: o `JAVA_HOME` da máquina aponta para um JRE 8. Use `JAVA_HOME="C:\Program Files\Java\jdk-26.0.1"`.

### 4.3 `ddl-auto=update` pode alterar tabela de outro serviço

`application-dev.properties` do gestor usa `spring.jpa.hibernate.ddl-auto=update`. As entidades novas mapeiam `indicador_fundamentalista`, que é **escrita pelo ETL Python**. Divergência de mapeamento faz o Hibernate alterar a tabela por baixo. Troque para `validate` — mas confira antes que o mapeamento bate coluna a coluna.

### 4.4 Chaves reais em arquivo não versionado — `infra#ISS-01`

`docker-compose-local.yml` tem `BRAPI_API_KEY` e `GEMINI_API_KEY` reais em texto puro. Está no `.gitignore` desde `4c0480f`, o que evita o vazamento mas cria outro problema: **o serviço do ETL adicionado ali não é versionado**. Mover para `.env` com `env_file` resolve os dois.

### 4.5 `mysql-init` só roda em volume novo — `infra#ISS-03`

O MySQL só executa `docker-entrypoint-initdb.d` na **primeira** criação do volume. Tabela nova no schema não aparece em banco que já existia. O ETL detecta e explica (`VerificadorDeSchema`), mas o problema de fundo — ninguém é dono do schema, `infra#DEC-01` está ABERTO — continua.

Para aplicar sem perder dado (o script é todo `CREATE TABLE IF NOT EXISTS`):

```bash
docker exec -i mysql mysql -uspring -pspring123 minha_base < "infra-b3-ecossytem/mysql-init/1 - schema.sql"
```

### 4.6 Itens menores

- **`RENT3` diverge 43,8% do Fundamentus** sem explicação (`ISS-E04`). A DRE extraída fecha internamente (`3.09` = `3.11`, sem operação descontinuada), então a extração é fiel ao arquivo da CVM.
- **Plano de contas de seguradora não exercitado** (`ISS-E05`): o código existe, nenhum ticker testado caiu nele.
- **ROIC é convenção, não fato** (`ISS-E03`): usa alíquota nominal de 34% e definição própria de capital investido. Damos 31,3% na WEG contra 24,3% do Fundamentus.
- **`BPAC11` não tem ticker no FCA**: o ETL avisa e segue. Vale investigar se outros *units* têm o mesmo problema.
- **Vocabulário de recomendação fragmentado** (`gerar-insights#DEC-05`): `COMPRA_FORTE`, `COMPRA_TECNICA` e o consolidador Java usam vocabulários diferentes. Precisa de decisão de contrato entre serviços.

---

## 5. Convenções obrigatórias

### Git

**Nunca abra PR manualmente.** O fluxo é commit + push; branches `feature**` abrem PR automaticamente via workflow. Mensagens de commit explicam o *porquê*, não só o *o quê*.

### Specs

Os quatro repositórios tratam `SPEC.md` como contrato, com IDs estáveis (`REQ-`, `NFR-`, `ISS-`, `TASK-`, `DEC-`, `CTR-`). Regras que valem aqui:

- **IDs nunca são renumerados nem apagados.** Para aposentar, use status `DESCARTADO` com justificativa.
- Mudança em regra financeira exige subir `versao_payload` e atualizar a spec **no mesmo PR**.
- Mudança em tabela compartilhada é mudança de contrato: atualize o `CTR-` em `infra-b3-ecossytem/SPEC.md` e avise os outros serviços.
- Critérios de aceite em Dado/Quando/Então.

### Código

- **Nomes em português** (`Servico*`, `Repositorio*`, `Montador*`, `avaliar`, `carregar`).
- No front, todo arquivo abre com `// Unica responsabilidade: ...` e **não se escreve CSS próprio** — tudo vem de classes do Bootstrap. `public/css/app.css` tem 10 linhas e só cobre o que o Bootstrap não faz.
- No `etl-fundamentos-cvm`: injeção por construtor com argumentos **obrigatórios** (sem `x or ClasseConcreta()`), commit só na unidade de trabalho, domínio sem importar SQLAlchemy/boto3/requests. `ruff check`, `mypy app` e `pytest` precisam passar.
- No front, `npm test` roda os testes do detector em node puro, sem framework.

### Vocabulário

Termos de mercado e de engenharia estão em [`GLOSSARIO.md`](GLOSSARIO.md), espelhado na aba `#/glossario` do painel. **Os dois devem ser atualizados juntos.**

---

## 6. Aviso regulatório

`gerar-insights#ISS-F6`: rótulos de COMPRA/VENDA podem configurar recomendação de investimento sob a Res. CVM 20/2021. O painel apresenta indicador contábil e material informativo, não sugestão de operação. Mantenha esse enquadramento em qualquer texto novo.
