-- Comunicados oficiais das companhias abertas (base IPE dos dados abertos da
-- CVM): fatos relevantes, comunicados ao mercado, avisos aos acionistas,
-- proventos, calendario e resultados. Escrita pelo etl-fundamentos-cvm
-- (`--comunicados`), lida pelo gestor-ativos-brutos. Contrato: CTR-08.
--
-- Chave natural: `protocolo_cvm`, o numProtocolo do link de download. O campo
-- Protocolo_Entrega do CSV NAO serve de chave: vem vazio nos relatorios de
-- proventos gerados automaticamente (501 linhas em 2026) e repete em linhas
-- duplicadas. A base publica so a versao vigente de cada documento; a coluna
-- `versao` guarda qual foi.
--
-- A tabela guarda CNPJ, nao ticker: uma empresa tem varios tickers (ON, PN,
-- unit). A traducao e feita na leitura, juntando com cvm_ticker.
--
-- CREATE TABLE IF NOT EXISTS: segura sobre volumes que ja receberam a tabela
-- pelo mysql-init.

CREATE TABLE IF NOT EXISTS comunicado_cvm (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    protocolo_cvm VARCHAR(20) NOT NULL,
    protocolo_entrega VARCHAR(40) NULL,
    versao SMALLINT NOT NULL DEFAULT 1,

    cnpj VARCHAR(20) NOT NULL,
    codigo_cvm VARCHAR(10) NULL,

    categoria VARCHAR(40) NOT NULL,
    categoria_original VARCHAR(200) NOT NULL,
    tipo VARCHAR(120) NULL,
    especie VARCHAR(120) NULL,
    assunto TEXT NULL,

    data_referencia DATE NULL,
    data_entrega DATE NOT NULL,
    link_download VARCHAR(300) NOT NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_comunicado_cvm_protocolo (protocolo_cvm),
    INDEX idx_comunicado_cvm_cnpj_data (cnpj, data_entrega),
    INDEX idx_comunicado_cvm_categoria_data (categoria, data_entrega),
    INDEX idx_comunicado_cvm_data (data_entrega),
    FULLTEXT KEY ft_comunicado_cvm_assunto (assunto)
);
