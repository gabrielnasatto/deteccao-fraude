-- =====================================================================
-- 01_abt.sql
-- Constrói a abt_fraude: 1 linha por transação, 20 colunas (features + rótulo),
-- pronta para treinar um modelo de detecção de fraude.
-- Dialeto: DuckDB (pré-requisito: 00_carregar_dados.sql já executado).
-- =====================================================================
--
-- Decisões:
-- 1. Tabelas que entram: transacoes + scores_comportamentais + scores_financeiros
--    + scores_modelo. dim_paises e dim_categorias não contribuem com nenhuma coluna
--    do alvo: elas são usadas só na análise (02_analises.sql).
-- 2. JOIN: as 4 tabelas têm o MESMO grão (1 linha por id_transacao, 150.200 ids
--    únicos em cada uma, todos presentes nas 4). Por isso um INNER JOIN 1:1 por
--    id_transacao não duplica nem perde linhas.
-- 3. Filtro: is_teste = 0. A base bruta tem 200 transações de teste (QA/homologação).
--    Elas não são comportamento real de cliente e contaminariam o treino.
--    150.200 - 200 = 150.000 linhas.
-- 4. Colunas listadas explicitamente, na ordem do alvo. Metadados (canal_venda,
--    versao_api, dt_calculo_score, moeda_calculo, experimento, threshold etc.) ficam de fora.
-- 5. As colunas entrega_doc_* são mantidas como vieram, para reproduzir o alvo exatamente.
--    Atenção na modelagem: doc_1 é 1/0, doc_2 e doc_3 são 'Y'/'N' e doc_2 tem ~73% de nulos.
--    Elas precisam ser padronizadas na etapa de feature engineering.

CREATE OR REPLACE TABLE abt_fraude AS
SELECT
    sc.score_1,
    sc.score_2,
    sf.score_3,
    sc.score_4,
    sc.score_5,
    sf.score_6,
    t.pais,
    sc.score_7,
    t.produto,
    t.categoria_produto,
    sm.score_8,
    sf.score_9,
    sf.score_10,
    t.entrega_doc_1,
    t.entrega_doc_2,
    t.entrega_doc_3,
    t.data_compra,
    t.valor_compra,
    sm.score_fraude_modelo,
    sm.fraude
FROM transacoes                   AS t
INNER JOIN scores_comportamentais AS sc ON sc.id_transacao = t.id_transacao
INNER JOIN scores_financeiros     AS sf ON sf.id_transacao = t.id_transacao
INNER JOIN scores_modelo          AS sm ON sm.id_transacao = t.id_transacao
WHERE t.is_teste = 0;


-- =====================================================================
-- Verificações de aceite
-- =====================================================================

-- (a) Linhas: deve retornar 150000
SELECT COUNT(*) AS linhas FROM abt_fraude;

-- (b) Colunas: deve retornar 20
SELECT COUNT(*) AS colunas
FROM information_schema.columns
WHERE table_name = 'abt_fraude';

-- (c) Ordem das colunas (conferir visualmente com o alvo)
DESCRIBE abt_fraude;

-- (d) Grão: cada id de transação aparece 1 vez nas tabelas de origem,
--     então o JOIN 1:1 não pode ter duplicado nada (esperado: 0 ids repetidos)
SELECT COUNT(*) - COUNT(DISTINCT id_transacao) AS ids_duplicados
FROM transacoes;

-- (e) Sanidade do rótulo: fraude ~5%
SELECT
    SUM(fraude)                AS fraudes,
    ROUND(AVG(fraude) * 100, 2) AS taxa_fraude_pct
FROM abt_fraude;
