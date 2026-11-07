-- =====================================================================
-- 00_carregar_dados.sql
-- Carrega os 6 CSVs brutos (data/raw/) para o banco DuckDB fraude.duckdb
-- =====================================================================

-- Pasta onde estão os CSVs. O caminho relativo funciona ao rodar pelo CLI a partir da pasta do projeto.
-- No DBeaver, troque pelo caminho ABSOLUTO da pasta data/raw da sua máquina
-- (use barras "/" mesmo no Windows). Os read_csv_auto abaixo usam caminho relativo a ela.
SET file_search_path = 'data/raw';


-- 1. Carga das tabelas -------------------------------------------------
CREATE OR REPLACE TABLE transacoes             AS SELECT * FROM read_csv_auto('transacoes.csv');
CREATE OR REPLACE TABLE scores_comportamentais AS SELECT * FROM read_csv_auto('scores_comportamentais.csv');
CREATE OR REPLACE TABLE scores_financeiros     AS SELECT * FROM read_csv_auto('scores_financeiros.csv');
CREATE OR REPLACE TABLE scores_modelo          AS SELECT * FROM read_csv_auto('scores_modelo.csv');
CREATE OR REPLACE TABLE dim_paises             AS SELECT * FROM read_csv_auto('dim_paises.csv');
CREATE OR REPLACE TABLE dim_categorias         AS SELECT * FROM read_csv_auto('dim_categorias.csv');


-- 2. Conferência de volume ---------------------------------------------
-- Esperado: transacoes / scores_* = 150.200 cada | dim_paises = 57 | dim_categorias = 8.374
SELECT 'transacoes' AS tabela, COUNT(*) AS linhas FROM transacoes
UNION ALL SELECT 'scores_comportamentais', COUNT(*) FROM scores_comportamentais
UNION ALL SELECT 'scores_financeiros',     COUNT(*) FROM scores_financeiros
UNION ALL SELECT 'scores_modelo',          COUNT(*) FROM scores_modelo
UNION ALL SELECT 'dim_paises',             COUNT(*) FROM dim_paises
UNION ALL SELECT 'dim_categorias',         COUNT(*) FROM dim_categorias;


-- 3. Perfil das colunas de transacoes ----------------------------------
DESCRIBE transacoes;

SELECT entrega_doc_1, COUNT(*) FROM transacoes GROUP BY 1 ORDER BY 2 DESC;
SELECT entrega_doc_2, COUNT(*) FROM transacoes GROUP BY 1 ORDER BY 2 DESC;
SELECT entrega_doc_3, COUNT(*) FROM transacoes GROUP BY 1 ORDER BY 2 DESC;
SELECT is_teste,      COUNT(*) FROM transacoes GROUP BY 1 ORDER BY 2 DESC;

SELECT MIN(data_compra), MAX(data_compra), MIN(valor_compra), MAX(valor_compra)
FROM transacoes;

-- Achados:
-- * entrega_doc_1 = BIGINT 1/0 (135.535 / 14.665)
-- * entrega_doc_2 = VARCHAR 'Y'/'N'/NULL (24.126 / 17.075 / 108.999 nulos)
-- * entrega_doc_3 = VARCHAR 'Y'/'N' (83.243 / 66.957)
--   => mesma informação em 3 formatos; na ABT, padronizar para 1/0.
-- * is_teste = 1 em 200 linhas -> explica 150.200 vs 150.000; filtrar is_teste = 0.
-- * data_compra: TIMESTAMP de 08/03/2020 a 21/04/2020 (~6 semanas).
-- * valor_compra: DOUBLE de 0,02 a 3.696,35, sem nulos nem negativos.
