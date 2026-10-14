-- A chave e o efeito de negocio sao confirmados na mesma transacao.
-- INSERT IGNORE concorrente espera a transacao anterior; rollback libera retry.
CREATE TABLE IF NOT EXISTS evento_processado (
    consumidor VARCHAR(40) NOT NULL,
    dedup_key VARCHAR(64) NOT NULL,
    processado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (consumidor, dedup_key)
) ENGINE=InnoDB;
