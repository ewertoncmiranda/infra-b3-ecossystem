# Glossário do ecossistema B3

Vocabulário de mercado e de engenharia usado nos quatro repositórios, explicado
para quem nunca comprou uma ação. É a fonte canônica: as seções "Glossário" das
specs apontam para cá em vez de manter definição própria.

A versão navegável, com busca, está no painel em `#/glossario`
(`painel-ativos-frontend/public/js/pages/GlossarioPage.js`). Os dois devem ser
atualizados juntos.

Três regras de redação:

1. Nenhum termo é definido usando outro termo ainda não definido — por isso a
   ordem das seções importa.
2. Todo verbete diz onde aquilo aparece **neste sistema**, senão vira dicionário
   genérico.
3. Indicador vem com faixa de referência **e** com a ressalva de que faixa boa
   varia por setor: margem líquida de 2% é ótima para supermercado e péssima
   para software.

> Material informativo, não recomendação de investimento. Explicar o que é P/L
> não é sugerir compra. Ver `gerar-insights#ISS-F6` sobre a Res. CVM 20/2021.

---

## Onde as ações são negociadas

| Termo | O que é |
|---|---|
| **Ação** | Um pedaço da empresa. Quem tem 1 ação de 1.000 existentes é dono de 0,1% dela — dos lucros e dos prejuízos. |
| **B3** | A bolsa de valores brasileira, onde as ações são compradas e vendidas. Nome antigo: Bovespa. |
| **Ticker** (código de negociação) | O apelido da ação no pregão. `PETR4`, `WEGE3`. As letras são a empresa, o número diz o tipo. |
| **ON / PN** | `3` no fim do ticker = ação **ordinária** (dá direito a voto nas assembleias). `4` = **preferencial** (geralmente sem voto, mas com preferência no recebimento de dividendos). `11` = *unit*, um pacote que junta as duas. |
| **Pregão** | O dia de negociação. "Fechamento do pregão" é o preço do último negócio do dia. |
| **Companhia aberta** | Empresa autorizada a vender ações ao público. Em troca, é obrigada a publicar seus números — é essa obrigação que torna este projeto possível. |
| **CVM** | Comissão de Valores Mobiliários, o órgão do governo que fiscaliza o mercado. Publica de graça tudo o que as empresas são obrigadas a entregar. |
| **Free float** | A fatia das ações que realmente circula no mercado, fora das mãos dos controladores. |
| **Ações em tesouraria** | Ações que a própria empresa recomprou e mantém guardadas. Não valem dividendo nem voto, então saem da conta ao dividir lucro por ação. |
| **Acionista controlador / minoritário** | Controlador manda na empresa; minoritário só acompanha. Relevante porque parte do lucro pertence a sócios de outras empresas do grupo — e o mercado calcula os indicadores só sobre a parte do controlador. |

## Os documentos que a empresa é obrigada a publicar

| Sigla | O que é |
|---|---|
| **DFP** | Demonstrações Financeiras Padronizadas — o "boletim anual" da empresa. Sai uma vez por ano, com os números auditados do exercício fechado. |
| **ITR** | Informações Trimestrais — a versão a cada 3 meses, mais rápida e menos auditada. |
| **FCA** | Formulário Cadastral — quem é a empresa: CNPJ, endereço, e **quais tickers ela tem na B3**. É o que permite ligar `WEGE3` ao CNPJ da WEG. |
| **FRE** | Formulário de Referência — o dossiê completo. Neste projeto ele é usado por um motivo específico: é a fonte confiável da **quantidade de ações**. |
| **Exercício social** | O "ano" contábil da empresa. Quase sempre janeiro a dezembro. |
| **Reapresentação** | Quando a empresa republica um balanço corrigido. Por isso todo arquivo tem um número de **versão**, e só a maior vale. |
| **Consolidado × individual** | Consolidado soma a empresa e todas as suas controladas; individual é só a matriz. Comparações de mercado usam o consolidado. |

## As peças do balanço

| Termo | O que é |
|---|---|
| **Balanço patrimonial** | A foto do que a empresa **tem** e **deve** num dia específico. |
| **Ativo** | Tudo o que a empresa tem: caixa, estoque, fábrica, máquina. |
| **Passivo** | Tudo o que ela deve: fornecedor, banco, imposto. |
| **Patrimônio líquido (PL)** | Ativo menos passivo — o que sobraria para os donos se tudo fosse liquidado hoje. |
| **Circulante × não circulante** | Circulante vence em até 12 meses; não circulante, depois. Separa dívida urgente de dívida de longo prazo. |
| **DRE** | Demonstração do Resultado do Exercício — o **filme** do ano: quanto entrou de receita, quanto saiu de custo, quanto sobrou de lucro. (O balanço é foto; a DRE é filme.) |
| **Receita líquida** | Tudo o que a empresa vendeu, já sem os impostos sobre a venda. |
| **EBIT** | Lucro antes de juros e impostos — o resultado só da operação, ignorando dívida e governo. Mede se o negócio em si funciona. |
| **EBITDA** | O EBIT somado à depreciação e amortização (despesas que não saem do caixa). Aproxima a geração de caixa da operação. |
| **Lucro líquido** | O que sobrou no fim de tudo — depois de custo, despesa, juros e imposto. É o número que vira dividendo. |
| **DFC** | Demonstração dos Fluxos de Caixa — o dinheiro que de fato entrou e saiu, dividido em operação, investimento e financiamento. Lucro é opinião contábil; caixa é fato. |
| **Capex** | Gasto em bens duráveis: fábrica, máquina, obra. |
| **Fluxo de caixa livre (FCL)** | O caixa que sobra depois de manter a operação de pé. É dele que saem dividendos e quitação de dívida. |
| **Caixa e equivalentes** | Dinheiro disponível na hora. |
| **Dívida bruta × dívida líquida** | Bruta é tudo o que se deve a bancos; líquida desconta o caixa. Empresa com mais caixa que dívida tem dívida líquida **negativa** — e isso é bom. |
| **Provisões** | Dinheiro reservado para uma despesa provável mas ainda não paga, tipo um processo na justiça. |

## Os indicadores

Cada um responde uma pergunta diferente. Nenhum decide sozinho.

| Sigla | Conta | Pergunta que responde | Referência |
|---|---|---|---|
| **LPA** | lucro líquido ÷ nº de ações | Quanto de lucro cabe a cada ação? | Comparar só com o histórico da própria empresa |
| **VPA** | patrimônio líquido ÷ nº de ações | Quanto de patrimônio cabe a cada ação? | idem |
| **P/L** | preço ÷ LPA | Em quantos anos o lucro atual paga o preço da ação? | 8–15 costuma ser normal; muito baixo às vezes é armadilha |
| **P/VP** | preço ÷ VPA | Estou pagando quanto por cada R$ 1 de patrimônio? | Abaixo de 1 = abaixo do patrimônio contábil |
| **ROE** | lucro líquido ÷ patrimônio líquido | A empresa rende bem sobre o dinheiro dos sócios? | Acima de 15% é considerado bom |
| **ROIC** | NOPAT ÷ capital investido | E sobre todo capital, incluindo o dos bancos? | Precisa superar o custo da dívida |
| **NOPAT** | EBIT × (1 − alíquota) | Lucro da operação já descontado o imposto | — |
| **Margem líquida** | lucro líquido ÷ receita | De cada R$ 100 vendidos, quanto vira lucro? | Varia muito: supermercado 2%, software 30% |
| **Earnings yield** | LPA ÷ preço | O inverso do P/L, em %. Facilita comparar com a Selic | — |
| **Dividend yield** | dividendos ÷ preço | Quanto a ação paga por ano, em % | — |
| **Beta** | — | Mede o quanto a ação balança em relação à bolsa. Acima de 1, oscila mais | — |
| **TTM** | — | *Trailing twelve months*: os últimos 12 meses corridos, em vez do ano fechado. **É a diferença que faz o número deste projeto não bater com o de outros sites** | — |

## Como se analisa

| Termo | O que é |
|---|---|
| **Análise fundamentalista** | Olha o negócio: lucro, dívida, crescimento. Pergunta "esta empresa vale o preço?". É o que a CVM alimenta. |
| **Análise técnica** | Olha só o gráfico de preço e volume. Pergunta "para onde o preço está indo?". |
| **Valuation** | O exercício de estimar quanto a empresa deveria valer. |
| **Fórmula de Graham** | Um cálculo simples de preço justo criado por Benjamin Graham. A versão usada aqui é `preço justo = LPA × (8,5 + 2 × crescimento)`, onde 8,5 seria o múltiplo de uma empresa que não cresce. O projeto roda três cenários de crescimento: 0%, 3% e 5%. |
| **Margem de segurança** | Quanto o preço justo está acima do preço de mercado, em %. Positiva sugere desconto; negativa, que está caro. Graham defendia só comprar com margem folgada, porque a conta pode estar errada. |
| **OHLCV / candle** | Os cinco números de um dia de pregão: abertura, máxima, mínima, fechamento e volume. |
| **Volume** | Quantidade negociada. Volume alto dá mais confiança ao movimento de preço. |
| **Média móvel** | A média do preço dos últimos N dias, que se atualiza a cada dia. Suaviza o ruído e mostra a tendência. |
| **Z-score** | Quantos "desvios normais" o preço de hoje está longe da média. Perto de 0 é normal; acima de 2, anormalmente esticado. |
| **Momentum** | Estratégia que aposta na continuação: subindo, tende a continuar. |
| **Reversão à média** | A aposta oposta: o que esticou demais tende a voltar. |
| **Máxima / mínima de 52 semanas** | O maior e o menor preço do último ano. Serve de régua para saber onde o preço está hoje. |

## O que a empresa paga ao acionista

| Termo | O que é |
|---|---|
| **Provento** | Nome guarda-chuva para tudo o que a empresa entrega ao acionista. |
| **Dividendo** | Parte do lucro paga em dinheiro. No Brasil é isento de imposto de renda para a pessoa física. |
| **JCP** | Juros sobre Capital Próprio — parecido com dividendo, mas a empresa abate do imposto dela e o investidor paga 15% na fonte. |
| **Bonificação** | A empresa entrega ações novas de graça em vez de dinheiro. |
| **Desdobramento** (*split*) | Cada ação vira várias, e o preço cai na mesma proporção. Não muda o valor total — só deixa a ação mais acessível. |
| **Grupamento** | O contrário: várias ações viram uma, e o preço sobe proporcionalmente. |
| **Subscrição** | O direito de comprar ações novas antes do resto do mercado, normalmente com desconto. |

## Indicadores da economia

| Sigla | O que é |
|---|---|
| **Selic** | A taxa básica de juros do país, definida pelo Banco Central. É o "rendimento sem risco" — qualquer ação precisa render mais que ela para compensar. |
| **CDI** | Taxa que os bancos cobram entre si, quase sempre colada na Selic. É a régua da renda fixa. |
| **IPCA** | A inflação oficial. Rendimento abaixo dele é perda de poder de compra. |
| **IGP-M** | Outro índice de inflação, usado em contratos de aluguel. |
| **PTAX** | A cotação oficial do dólar, calculada pelo Banco Central. |

## Termos técnicos deste projeto

| Termo | O que é |
|---|---|
| **ETL** | *Extract, Transform, Load*: buscar o dado na fonte, arrumar, e gravar no banco. É o que o `etl-fundamentos-cvm` faz. |
| **Landing × mart** | Landing é o dado cru como veio (`fato_contabil`); mart é o dado pronto para consumo (`indicador_fundamentalista`). Guardar os dois permite recalcular sem rebaixar nada. |
| **De-para** | A tabela de tradução entre o nome da conta na CVM e o nome do indicador aqui. É a peça mais delicada do projeto, porque o mesmo código de conta significa coisas diferentes em empresas diferentes. |
| **Plano de contas** | O "índice" padronizado das contas contábeis. Banco, seguradora e indústria usam planos diferentes — daí a complicação. |
| **Idempotência** | Rodar duas vezes produzir o mesmo resultado que rodar uma. Sem isso, reprocessar duplica dado. |
| **Upsert** | Grava se não existe, atualiza se já existe. O mecanismo que garante a idempotência. |
| **ETag** | Uma "impressão digital" que o servidor da CVM dá a cada arquivo. Se não mudou, não precisa baixar de novo. |

---

## Onde cada termo aparece no código

| Termo | Onde olhar |
|---|---|
| De-para, plano de contas | `etl-fundamentos-cvm/app/dominio/plano_contas/` |
| LPA, VPA, ROE, ROIC | `etl-fundamentos-cvm/app/dominio/calculo/` |
| P/L, P/VP | `gestor-ativos-brutos` → `tools/CalculadoraMultiplos.java` (derivados na leitura) |
| Graham, margem de segurança | `gerar-insights/app/core/analysis/valuation.py` |
| Média móvel, z-score, momentum | `gerar-insights/app/core/analysis/technical_series.py` |
| DFP, ITR, FCA, FRE | `etl-fundamentos-cvm/app/adaptadores/cvm/fonte_cvm.py` |
| ETag, idempotência, upsert | `etl-fundamentos-cvm/app/adaptadores/persistencia/repositorios.py` |
