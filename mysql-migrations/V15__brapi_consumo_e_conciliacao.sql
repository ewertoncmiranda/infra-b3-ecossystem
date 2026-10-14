-- Contrato entre as 3 frentes do plano de atualizacao diaria (PLANO-ATUALIZACAO-DIARIA.md,
-- secao 4.1): orcamento de cota da BRAPI e conciliacao brapi x COTAHIST.

CREATE TABLE brapi_consumo (
  dia DATE NOT NULL,
  endpoint VARCHAR(40) NOT NULL,          -- quote | quote-lote | historical | profile
  quantidade INT NOT NULL DEFAULT 0,
  atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (dia, endpoint)
);

CREATE TABLE snapshot_fechamento_brapi (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  simbolo VARCHAR(12) NOT NULL,
  data_pregao DATE NOT NULL,
  abertura DECIMAL(14,4), maxima DECIMAL(14,4), minima DECIMAL(14,4),
  fechamento DECIMAL(14,4),               -- close BRUTO, nunca o ajustado
  volume BIGINT,
  horario_dado_brapi DATETIME NULL,       -- regularMarketTime da cotacao
  capturado_em DATETIME NOT NULL,
  status_captura VARCHAR(20) NOT NULL,    -- OK | ERRO_HTTP | SEM_DADO
  UNIQUE KEY uq_snapshot_fechamento_brapi (simbolo, data_pregao)
);

CREATE VIEW vw_conciliacao_preco AS
SELECT s.simbolo, s.data_pregao,
       s.fechamento AS fech_brapi, b.fechamento AS fech_b3,
       b.fechamento - s.fechamento                                   AS dif_fechamento,
       ROUND((b.fechamento - s.fechamento) / 0.01)                   AS dif_fechamento_ticks,
       ROUND((b.fechamento - s.fechamento) / b.fechamento * 100, 4)  AS dif_fechamento_pct,
       b.abertura - s.abertura AS dif_abertura,
       b.maxima - s.maxima     AS dif_maxima,
       b.minima - s.minima     AS dif_minima,
       b.volume - s.volume     AS dif_volume,
       ROUND((b.volume - s.volume) / NULLIF(b.volume, 0) * 100, 2)   AS dif_volume_pct,
       TIMESTAMPDIFF(MINUTE, s.horario_dado_brapi, s.capturado_em)   AS idade_dado_min,
       CASE
         WHEN s.status_captura <> 'OK'                                  THEN 'SEM_BRAPI'
         WHEN b.simbolo IS NULL AND CURRENT_DATE > s.data_pregao        THEN 'SEM_B3'
         WHEN b.simbolo IS NULL                                         THEN 'PENDENTE'
         WHEN ABS(b.fechamento - s.fechamento) >= 0.01
           OR ABS(b.maxima - s.maxima) >= 0.01
           OR ABS(b.minima - s.minima) >= 0.01                          THEN 'DIVERGENTE_PRECO'
         WHEN ABS(b.volume - s.volume) / NULLIF(b.volume, 0) > 0.01     THEN 'DIVERGENTE_VOLUME'
         ELSE 'OK'
       END AS divergencia,
       CASE
         WHEN b.simbolo IS NULL OR s.status_captura <> 'OK'                 THEN NULL
         WHEN ABS(b.fechamento - s.fechamento) >= 0.02
          AND ABS(b.fechamento - s.fechamento) / b.fechamento > 0.005       THEN 'GRAVE'
         WHEN ABS(b.fechamento - s.fechamento) >= 0.01                      THEN 'LEVE'
       END AS severidade
FROM snapshot_fechamento_brapi s
LEFT JOIN cotacao_b3_diaria b
       ON b.simbolo = s.simbolo AND b.data_pregao = s.data_pregao;
