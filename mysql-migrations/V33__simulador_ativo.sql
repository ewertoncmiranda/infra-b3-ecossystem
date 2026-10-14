-- SIM-INFRA-1: tabela raiz do Simulador de Operações.
-- Cada ativo monitorado tem janela fixa (imutável após cadastro) e capital inicial de referência.
-- Para alterar janela: marcar ativo=0 e inserir novo registro.

CREATE TABLE simulador_ativo (
    id              INT            NOT NULL AUTO_INCREMENT,
    simbolo         VARCHAR(10)    NOT NULL,
    janela_pregoes  INT            NOT NULL DEFAULT 63,
    capital_inicial DECIMAL(15,2)  NOT NULL DEFAULT 100000.00,
    data_inclusao   DATE           NOT NULL,
    ativo           TINYINT(1)     NOT NULL DEFAULT 1,

    CONSTRAINT pk_simulador_ativo PRIMARY KEY (id),
    CONSTRAINT uk_simulador_simbolo UNIQUE (simbolo),
    CONSTRAINT ck_simulador_janela  CHECK (janela_pregoes BETWEEN 1 AND 252),
    CONSTRAINT ck_simulador_capital CHECK (capital_inicial > 0)
);
