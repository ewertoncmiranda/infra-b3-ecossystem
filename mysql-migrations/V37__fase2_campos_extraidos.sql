-- V37: campos fase 2 do ETL de fundamentos CVM
--
-- indicador_fundamentalista
--   D3: estoques          BPA 1.01.04 — insumo de liquidez_seca e DIO
--   D4: contas_a_receber  BPA 1.01.03 — insumo de DSO (prazo medio de recebimento)
--   E2: despesas_pessoal  DVA 7.08.01 — remuneracao do trabalho
--
-- opcao_b3_diaria
--   C2: melhor_oferta_compra DECIMAL(14,4) — PREOFC pos 122-134 do COTAHIST
--   C2: melhor_oferta_venda  DECIMAL(14,4) — PREOFV pos 135-147 do COTAHIST

ALTER TABLE indicador_fundamentalista
    ADD COLUMN estoques         DECIMAL(24, 2) NULL COMMENT 'BPA 1.01.04 — fase 2 D3',
    ADD COLUMN contas_a_receber DECIMAL(24, 2) NULL COMMENT 'BPA 1.01.03 — fase 2 D4',
    ADD COLUMN despesas_pessoal DECIMAL(24, 2) NULL COMMENT 'DVA 7.08.01 — fase 2 E2';

ALTER TABLE opcao_b3_diaria
    ADD COLUMN melhor_oferta_compra DECIMAL(14, 4) NULL COMMENT 'PREOFC COTAHIST — fase 2 C2',
    ADD COLUMN melhor_oferta_venda  DECIMAL(14, 4) NULL COMMENT 'PREOFV COTAHIST — fase 2 C2';
