-- V39: indicadores derivados da fase 4 do ETL de fundamentos CVM
--
-- indicador_fundamentalista
--   I5 insumos:
--     ativo_circulante   DECIMAL(24,2) — BPA 1.01
--     passivo_circulante DECIMAL(24,2) — BPP 2.01
--   I1 derivado:
--     cobertura_juros    DECIMAL(14,4) — EBIT / |resultado_financeiro| (RF < 0)
--   I5 derivados:
--     liquidez_corrente  DECIMAL(10,4) — ativo_circulante / passivo_circulante
--     liquidez_seca      DECIMAL(10,4) — (ativo_circulante - estoques) / passivo_circulante
--   I6 derivado:
--     dso                DECIMAL(10,2) — contas_a_receber * 365 / receita_liquida (dias)
--   I8 derivado:
--     graham_number      DECIMAL(18,6) — sqrt(22.5 * LPA * VPA)
--
-- C4 (moeda_referencia para BDRs) e armazenado em serie_historica.detalhes_json,
-- nao exige coluna nova.

ALTER TABLE indicador_fundamentalista
    ADD COLUMN ativo_circulante   DECIMAL(24, 2) NULL COMMENT 'BPA 1.01 — fase 4 I5 insumo',
    ADD COLUMN passivo_circulante DECIMAL(24, 2) NULL COMMENT 'BPP 2.01 — fase 4 I5 insumo',
    ADD COLUMN cobertura_juros    DECIMAL(14, 4) NULL COMMENT 'EBIT / |RF| (RF<0) — fase 4 I1',
    ADD COLUMN liquidez_corrente  DECIMAL(10, 4) NULL COMMENT 'AC / PC — fase 4 I5',
    ADD COLUMN liquidez_seca      DECIMAL(10, 4) NULL COMMENT '(AC-Estoques) / PC — fase 4 I5',
    ADD COLUMN dso                DECIMAL(10, 2) NULL COMMENT 'prazo medio recebimento dias — fase 4 I6',
    ADD COLUMN graham_number      DECIMAL(18, 6) NULL COMMENT 'sqrt(22.5*LPA*VPA) — fase 4 I8';
