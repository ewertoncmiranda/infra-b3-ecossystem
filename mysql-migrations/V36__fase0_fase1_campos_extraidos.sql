-- V36__fase0_fase1_campos_extraidos.sql
-- Fase 0 (C1): indice_correcao em opcao_b3_diaria
--   INDOPC pos 202 do COTAHIST: "0"=sem correcao, "1"=SELIC, "2"=IGP-M.
--   Opcoes com indice != "0" tem strike que muda diariamente; sem este campo
--   o break-even calculado pelo ETL e incorreto em silencio.
--
-- Fase 1 (D1/D2): resultado_financeiro e passivo_nao_circulante em indicador_fundamentalista
--   D1: DRE 3.06+3.07 (receitas - despesas financeiras; negativo = despesa liq.)
--   D2: BPP 2.02 (passivo nao circulante — excluido de bancos e fins.)
--
-- Fase 1 (E1): impostos_dva em indicador_fundamentalista
--   DVA 7.08.02 (IR+CSLL reais); substitui a constante ALIQUOTA_NOMINAL=0.34
--   que superestima o imposto de empresas com beneficios fiscais.
--
-- Fase 1 (F1/F2): cnae e grupo_economico em cvm_empresa
--   Lidos da FCA (Codigo_CNAE, Grupo_Economico); permitem agrupar emissores
--   por atividade economica independente da classificacao setorial da CVM.

ALTER TABLE opcao_b3_diaria
    ADD COLUMN indice_correcao CHAR(1) NULL
        COMMENT '0=sem correcao, 1=SELIC, 2=IGP-M (COTAHIST pos 202)';

ALTER TABLE indicador_fundamentalista
    ADD COLUMN resultado_financeiro  DECIMAL(24, 2) NULL
        COMMENT 'DRE 3.06+3.07: receitas menos despesas financeiras',
    ADD COLUMN passivo_nao_circulante DECIMAL(24, 2) NULL
        COMMENT 'BPP 2.02: passivo de longo prazo (excluido bancos/fins.)',
    ADD COLUMN impostos_dva           DECIMAL(24, 2) NULL
        COMMENT 'DVA 7.08.02: IR+CSLL+contrib sociais reais (negativo=despesa)';

ALTER TABLE cvm_empresa
    ADD COLUMN cnae            VARCHAR(7)   NULL
        COMMENT 'Codigo CNAE da FCA (ex.: 6619-3/99)',
    ADD COLUMN grupo_economico VARCHAR(200) NULL
        COMMENT 'Grupo economico da FCA (ex.: PETROBRAS)';
