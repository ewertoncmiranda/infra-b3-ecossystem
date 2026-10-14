-- V18__empresa_situacao_registro.sql
-- TASK-E13: situacao do registro CVM, data de constituicao e estado (UF) da empresa.
-- Permite distinguir empresa com registro cancelado de empresa ativa no painel;
-- sem isso uma delistagem silenciosa aparece como dado valido.
ALTER TABLE cvm_empresa
    ADD COLUMN situacao_registro VARCHAR(30) NULL AFTER setor,
    ADD COLUMN data_constituicao DATE        NULL AFTER situacao_registro,
    ADD COLUMN uf_municipio      VARCHAR(2)  NULL AFTER data_constituicao;
