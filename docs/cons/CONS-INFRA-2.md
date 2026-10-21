# CONS-INFRA-2 — IMPLEMENTADO (2026-10-20)

## Entregue

- `SPEC.md`, seção "Plano consolidado CONS": nova subseção **"Contrato V45 (CONS-INFRA-2)"** no fim do arquivo. Traz, para cada uma das 9 tabelas novas, fonte e URL, periodicidade, etapa que grava, chave única, regra de upsert, quem lê (rótulo FONTES-GES-* ou MICRO-GES-*) e a tabela de colunas com tipo e nulidade.
- Também na subseção: regra do `hash_linha`, mapa TPMERC, mapa das marcas ex (marcado "a validar contra o layout oficial da B3, DEC-MICRO-1"), CHECKs ampliadas, o que saiu do plano (com o motivo), DEC-FONTES-1 e DEC-FONTES-3, e o bloco "Ordem de aplicação e rollback" (sem `down -v` nem `volume prune`).
- Status: CONS-INFRA-1 e CONS-INFRA-2 passaram a IMPLEMENTADO. A nota de CONS-INFRA-1 diz que a V45 foi escrita em feature-cons-infra-1, testada em base descartável e ainda não aplicada na base local.
- Nenhum código nem migration foi alterado. Sem commit nem push.

## Evidência

- Comparei cada tabela com `V45__fontes_publicas_e_microestrutura.sql` por script: as tabelas de colunas da SPEC foram geradas a partir do SQL e depois conferidas de volta contra ele (nome, tipo e NULL/NOT NULL). Foram 130 colunas nas 9 tabelas, com 0 divergências.
- Conferi à mão chaves únicas, índices e as CHECKs (`ck_data_ex_b3_tipo`, `ck_negociacao_b3_diaria_tpmerc` com 012, 013, 017, 020, 030, 050, 060, `ck_carga_etapa_etapa` com 17 etapas, `chk_etl_execucao_status` com INCOMPLETO) e a ausência de `fii_informe_mensal`.
- Fontes, URLs e periodicidade vêm de FONTES-ETL-1 (CVM), FONTES-ETL-3, 4, 5 e 7 (leitores) e do `fonte_tesouro.py`. A DEC-FONTES-3 usa o achado de FONTES-ETL-5 (15/10/2026, IPCA+ com Juros Semestrais 15/08/2032, 6,79%).
- O arquivo manteve CRLF em todas as linhas (sem LF solto) e continua sem BOM.

## Desvios

1. A linha CONS-INFRA-1 listava `cvm_recompra`, `cvm_politica_dividendos` e `cvm_divida_vencimento` e não listava `cvm_auditor`. Isso contradizia a V45 real. Corrigi para as 9 tabelas reais e anotei o que saiu e a renomeação.
2. A V45 aceita TPMERC 050 e 060 na CHECK, mas o plano só pedia 012, 013, 017, 020 e 030. O contrato registra 050 e 060 como aceitos, sem leitor e com descrição a validar.
3. A regra de serialização do `hash_linha` (ordem das colunas, `|` como separador, NULL vazio, datas ISO) não está em nenhum doc nem no SQL; a V45 só exige CHAR(64). Escrevi como convenção a ser fixada em código por FONTES-ETL-8.
4. O mapa das marcas ex tem duas hipóteses não confirmadas: `EX` como DESDOBRAMENTO e a precedência das combinações. Ambas estão sinalizadas como DEC-MICRO-1.
5. `cvm_divida_valor_mobiliario` e `negociacao_b3_diaria` não têm endpoint do gestor no plano; o contrato diz isso em vez de inventar um rótulo.
6. O IF.data não tem doc de entrega do leitor (FONTES-ETL-6) nem URL; o contrato cita só a API OData do BCB e deixa a URL para o leitor.
7. Na seção do plano CONS, o cabeçalho "Status: PLANEJADO" não foi alterado.
