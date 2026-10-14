-- V31__opcao_b3_saneamento_legado.sql
-- OPT-INFRA-2: saneamento idempotente do legado contaminado de opcoes.
--
-- Nao apaga historico. Apenas impede que registros antigos, carregados antes
-- do contrato de validacao, aparecam como cadeia operacional valida.
-- A ordem dos UPDATEs preserva o motivo mais especifico observado.

UPDATE opcao_b3_diaria
   SET status_validacao = 'REJEITADA',
       motivo_rejeicao = 'VENCIMENTO_INVALIDO_9999'
 WHERE status_validacao = 'LEGADO_NAO_VALIDADO'
   AND data_vencimento = '9999-12-31';

UPDATE opcao_b3_diaria
   SET status_validacao = 'REJEITADA',
       motivo_rejeicao = 'STRIKE_INVALIDO'
 WHERE status_validacao = 'LEGADO_NAO_VALIDADO'
   AND preco_exercicio <= 0;

UPDATE opcao_b3_diaria
   SET status_validacao = 'INCOMPLETA',
       motivo_rejeicao = 'ATIVO_OBJETO_AUSENTE'
 WHERE status_validacao = 'LEGADO_NAO_VALIDADO'
   AND ativo_objeto IS NULL;

UPDATE opcao_b3_diaria
   SET status_validacao = 'INCOMPLETA',
       motivo_rejeicao = 'TIPO_OPCAO_AUSENTE'
 WHERE status_validacao = 'LEGADO_NAO_VALIDADO'
   AND tipo_opcao IS NULL;
