-- V21__setor_grupo_classificado.sql
-- LAC-INFRA-2 (plano LAC, L7): classifica os 41 setores do FCA que a V16
-- deixou em 'A_CLASSIFICAR'. O plano previa isso dentro da V16, mas ela ja
-- estava aplicada (migration aplicada nao se edita).
--
-- Criterio: o percentil por setor do gerar-insights (app/fatores/percentis.py)
-- so existe com MINIMO_GRUPO = 5 papeis no grupo, entao sao poucos grupos e
-- grandes - setor com menos de 5 empresas entra no vizinho economico mais
-- proximo. "Emp. Adm. Part. - X" (holding de X) vai para o grupo de X.
--
-- regra_valuation e a sugestao para quem for comparar valor no grupo:
--   PVP_SETOR   balanco e o ativo (financeiras, construtoras)
--   DIVIDENDOS  regulados com payout alto (energia, saneamento, telecom)
--   PL_SETOR    ciclicos (lucro de pico engana o Graham) e asset-light
--   GRAHAM      o resto (padrao da V16)
--
-- LIKE sobre trechos sem acento: o texto do FCA vem com acento e o casamento
-- exato dependeria da codificacao de quem roda o script.

UPDATE setor_grupo SET grupo_setor = CASE
    WHEN setor_cvm LIKE '%Bancos%'
      OR setor_cvm LIKE '%Intermedia%Financeira%'
      OR setor_cvm LIKE 'Bolsas de Valores%'                THEN 'FINANCEIRO'
    WHEN setor_cvm LIKE '%Seguradoras e Corretoras%'        THEN 'SEGUROS'
    WHEN setor_cvm LIKE '%Energia El%trica%'
      OR setor_cvm LIKE 'Saneamento%'
      OR setor_cvm LIKE 'Telecomunica%'                     THEN 'UTILIDADES'
    WHEN setor_cvm LIKE '%Petr%leo e G%s%'
      OR setor_cvm LIKE '%Extra%o Mineral%'
      OR setor_cvm LIKE '%Metalurgia e Siderurgia%'
      OR setor_cvm LIKE 'Papel e Celulose%'
      OR setor_cvm LIKE 'Petroqu%micos%'                    THEN 'COMMODITIES'
    WHEN setor_cvm LIKE '%Alimentos%'
      OR setor_cvm LIKE 'Agricultura%'
      OR setor_cvm LIKE 'Bebidas e Fumo%'                   THEN 'AGRO_ALIMENTOS'
    WHEN setor_cvm LIKE '%Com%rcio (Atacado e Varejo)%'
      OR setor_cvm LIKE '%Com%rcio%'
      OR setor_cvm LIKE 'T%xtil e Vestu%rio%'
      OR setor_cvm LIKE 'Brinquedos e Lazer%'
      OR setor_cvm LIKE 'Hospedagem e Turismo%'
      OR setor_cvm LIKE '%Educa%o%'                         THEN 'CONSUMO_SERVICOS'
    WHEN setor_cvm LIKE 'Servi%os m%dicos%'
      OR setor_cvm LIKE 'Farmac%utico e Higiene%'           THEN 'SAUDE'
    WHEN setor_cvm LIKE '%Constru%o Civil%'
      OR setor_cvm LIKE '%Const. Civil%'                    THEN 'CONSTRUCAO_IMOBILIARIO'
    WHEN setor_cvm LIKE '%Transporte e Log%stica%'          THEN 'TRANSPORTE_LOGISTICA'
    WHEN setor_cvm LIKE 'Comunica%o e Inform%tica%'         THEN 'TECNOLOGIA'
    WHEN setor_cvm LIKE '%M%quinas, Equipamentos%'
      OR setor_cvm LIKE '%M%qs., Equip.%'
      OR setor_cvm LIKE 'Embalagens%'
      OR setor_cvm LIKE 'Gr%ficas e Editoras%'
      OR setor_cvm LIKE '%Sem Setor Principal%'             THEN 'INDUSTRIA_DIVERSOS'
    ELSE grupo_setor
END
WHERE grupo_setor = 'A_CLASSIFICAR';

UPDATE setor_grupo SET regra_valuation = CASE grupo_setor
    WHEN 'FINANCEIRO'             THEN 'PVP_SETOR'
    WHEN 'CONSTRUCAO_IMOBILIARIO' THEN 'PVP_SETOR'
    WHEN 'UTILIDADES'             THEN 'DIVIDENDOS'
    WHEN 'SEGUROS'                THEN 'PL_SETOR'
    WHEN 'COMMODITIES'            THEN 'PL_SETOR'
    WHEN 'SAUDE'                  THEN 'PL_SETOR'
    WHEN 'TECNOLOGIA'             THEN 'PL_SETOR'
    ELSE 'GRAHAM'
END
WHERE grupo_setor <> 'A_CLASSIFICAR';

-- Setor que o FCA trouxer depois da V16 (ou que esta V21 nao reconheceu)
-- continua 'A_CLASSIFICAR' e aparece aqui; nunca vira grupo por engano.
INSERT IGNORE INTO setor_grupo (setor_cvm, grupo_setor)
SELECT DISTINCT setor, 'A_CLASSIFICAR' FROM cvm_empresa WHERE setor IS NOT NULL;
