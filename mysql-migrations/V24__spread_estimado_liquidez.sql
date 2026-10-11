-- Plano OPR (OPR-ETL-2): spread estimado por maxima e minima, para quando o COTAHIST nao traz
-- ofertas suficientes. Escritor unico: etl-fundamentos-cvm (dentro da carga do COTAHIST).
--
-- spread_mediano_63d continua sendo o spread COTADO (melhor venda - melhor compra) / preco medio,
-- NULL com motivo quando ha menos de 20 dias com as duas ofertas. spread_estimado_63d e o
-- estimador de Corwin-Schultz (2012) sobre maxima/minima diarias (com ajuste do gap noturno),
-- media dos pares de pregoes consecutivos nos ultimos 63: existe tambem para o ativo sem ofertas.
-- Fracao (0.0052 = 0,52%); NULL com motivo em motivos_ausencia_json se houver menos de 20 pares.
-- Quem decide o custo e o gerar-insights (OPR-INS-5); o ETL so mede.
ALTER TABLE ativo_liquidez_diaria
    ADD COLUMN spread_estimado_63d DECIMAL(12,8) NULL AFTER spread_mediano_63d;
