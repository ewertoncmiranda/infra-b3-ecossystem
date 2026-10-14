-- V38: campos fase 3 do ETL de fundamentos CVM
--
-- indicador_fundamentalista
--   D5: depreciacao_amortizacao DECIMAL(24,2) — DFC_MI fragmento matching
--                                               insumo do EBITDA e FCL ajustado
--   D5: ebitda                  DECIMAL(24,2) — EBIT + D&A
--
-- cvm_ticker
--   G1: free_float DECIMAL(6,2) — % de ações em circulação livre
--       calculado como 100 - soma(Pct_Capital_Total) do FRE acionista_significativo

ALTER TABLE indicador_fundamentalista
    ADD COLUMN depreciacao_amortizacao DECIMAL(24, 2) NULL COMMENT 'DFC_MI fragmento deprecia+amortiza — fase 3 D5',
    ADD COLUMN ebitda                  DECIMAL(24, 2) NULL COMMENT 'EBIT + D&A — fase 3 D5 derivado';

ALTER TABLE cvm_ticker
    ADD COLUMN free_float DECIMAL(6, 2) NULL COMMENT 'FRE acionista_significativo 100-sum(pct) — fase 3 G1';
