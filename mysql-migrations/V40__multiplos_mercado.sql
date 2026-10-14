-- V40: multiplos de mercado em indicador_fundamentalista
--
-- Populados por AtualizarMetricasMercado (pos-ETL) ao cruzar
-- indicador_fundamentalista com serie_historica.
-- Ficam NULL ate que COTAHIST esteja disponivel para o periodo.
--
-- I4: pl_setorial_mediana — mediana do P/L das empresas do mesmo setor
--     agrupado pelo CNAE de 4 digitos (classe)
-- I7: pl          — Preco / LPA da empresa
--     ev_ebitda   — (market_cap + divida_liquida) / EBITDA

ALTER TABLE indicador_fundamentalista
    ADD COLUMN pl                  DECIMAL(10, 2) NULL COMMENT 'Preco / LPA — multiplo mercado I7',
    ADD COLUMN ev_ebitda           DECIMAL(10, 2) NULL COMMENT '(MktCap + DivLiq) / EBITDA — I7',
    ADD COLUMN pl_setorial_mediana DECIMAL(10, 2) NULL COMMENT 'mediana P/L setor CNAE[:4] — I4';
