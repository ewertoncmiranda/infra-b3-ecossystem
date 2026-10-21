# CONS-INFRA-1 — IMPLEMENTADO (2026-10-20)

## Entregue

`mysql-migrations/V45__fontes_publicas_e_microestrutura.sql`. É aditiva e idempotente: usa `CREATE TABLE IF NOT EXISTS`, e as CHECKs são recriadas com DROP condicional via `information_schema` + ADD.

| Tabela | Chave única |
|---|---|
| titulo_publico_taxa | (tipo, vencimento, data_base); índice (data_base) |
| banco_indicador_trimestral | (cnpj, data_base) |
| cvm_cadastro | PK cnpj |
| cvm_auditor | (cnpj, data_referencia, cnpj_auditor, data_inicio) |
| cvm_negociacao_administrador | (cnpj, data_referencia, versao, hash_linha) |
| cvm_divida_valor_mobiliario | (cnpj, data_referencia, versao, hash_linha) |
| fundo_posicao_acao | (competencia, cnpj_fundo, simbolo) |
| data_ex_b3 | (simbolo, data_ex, marca); CHECK `ck_data_ex_b3_tipo` |
| negociacao_b3_diaria | (simbolo, data_pregao, tpmerc); índice (simbolo_base, data_pregao); CHECK `ck_negociacao_b3_diaria_tpmerc` |

Constraints recriadas:
- `ck_carga_etapa_etapa`: as 11 etapas atuais + TESOURO, IFDATA, CVM_CADASTRO, CVM_VLMO, CVM_FRE, CVM_CDA.
- `chk_etl_execucao_status` (nome real no V1): EM_ANDAMENTO, SUCESSO, PULADO, ERRO, INCOMPLETO.

## Evidência

A verificação rodou na base descartável `v45_teste`, no container `mysql`, como root (a senha veio do env do container e não foi impressa). A `minha_base` não foi tocada.

1. `DROP DATABASE IF EXISTS v45_teste; CREATE DATABASE v45_teste;`
2. Todas as migrations, de V1 a V45, foram aplicadas em ordem (`sort -V`) com `docker cp` + `mysql v45_teste < /tmp/x.sql`. Depois a V45 rodou **uma segunda vez**. Nenhuma das execuções deu erro.
3. O `information_schema.CHECK_CONSTRAINTS` mostra as 4 CHECKs com as listas esperadas. O `information_schema.TABLES` mostra as 9 tabelas novas e confirma que `fii_informe_mensal` não existe.
4. `INSERT INTO etl_execucao(... status='INCOMPLETO')` foi aceito.
5. `INSERT INTO negociacao_b3_diaria(... tpmerc='010')` foi rejeitado com `ERROR 3819: Check constraint 'ck_negociacao_b3_diaria_tpmerc' is violated`.
6. `DROP DATABASE v45_teste;`

## Desvios

1. **DEC-FONTES-2: FIIs não entram.** Por decisão do usuário, a tabela `fii_informe_mensal` não foi criada e `CVM_FII` saiu da CHECK `ck_carga_etapa_etapa`.
2. **`hash_linha` CHAR(64)** foi adicionada em `cvm_negociacao_administrador` e em `cvm_divida_valor_mobiliario`. Essa coluna não está no inventário. As duas fontes não têm um identificador natural por linha, por isso a chave única é (cnpj, data_referencia, versao, hash_linha). O ETL precisa calcular o SHA-256 em hex das colunas de conteúdo.
3. As colunas de controle (`id`, `criado_em`/`atualizado_em`) foram adicionadas nas tabelas CVM, além das colunas do inventário.
4. `cvm_recompra` e `cvm_politica_dividendos` não foram criadas, como pede o inventário.
