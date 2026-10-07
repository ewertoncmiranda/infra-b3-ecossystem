-- V19__indicador_fco_bruto.sql
-- TASK-E17: FCO bruto da DFC metodo direto (recebimentos de clientes).
-- O catalogo de regras e o TTM ja reconhecem DFC_MD (TASK-E15); esta coluna
-- completa o wiring para o mart. Empresas com DFC indireta ficam NULL.
ALTER TABLE indicador_fundamentalista
    ADD COLUMN fco_bruto DECIMAL(24,2) NULL AFTER fluxo_caixa_operacional;
