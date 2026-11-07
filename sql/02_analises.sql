-- =====================================================================
-- 02_analises.sql
-- Análise de fraude sobre a abt_fraude (Parte 2 do case).
-- Dialeto: DuckDB. Pré-requisito: 00_carregar_dados.sql e 01_abt.sql executados.
--
-- Roteiro (problema -> onde está -> o modelo atual funciona? -> o que fazer):
--   1. Tamanho do problema
--   2. Onde a fraude se concentra (valor, documentos, horário, país, categoria, canal)
--   3. O score_fraude_modelo ordena o risco?
--   4. Simulação da recomendação (fila de revisão manual)
--
-- Convenção: sempre olhamos TAXA de fraude (fraudes / transações), não volume bruto,
-- porque fraude é rara (~5%). Ao rankear segmentos, usamos piso de volume.
-- =====================================================================


-- =====================================================================
-- 1. TAMANHO DO PROBLEMA
-- =====================================================================

-- 1.1 Quantas fraudes, quanto dinheiro e qual o ticket.
-- Resultado: 7.500 fraudes (5,0%) somando R$ 547 mil, ou seja 8,4% do valor transacionado.
-- O ticket médio da fraude (R$ 73) é ~1,7x o da compra legítima (R$ 42):
-- a fraude pesa mais no dinheiro do que na contagem.
SELECT
    COUNT(*)                                                         AS transacoes,
    SUM(fraude)                                                      AS fraudes,
    ROUND(AVG(fraude) * 100, 2)                                      AS taxa_fraude_pct,
    ROUND(SUM(valor_compra), 0)                                      AS valor_total,
    ROUND(SUM(valor_compra) FILTER (WHERE fraude = 1), 0)            AS valor_fraude,
    ROUND(100 * SUM(valor_compra) FILTER (WHERE fraude = 1)
              / SUM(valor_compra), 2)                                AS pct_valor_em_fraude,
    ROUND(AVG(valor_compra) FILTER (WHERE fraude = 1), 2)            AS ticket_medio_fraude,
    ROUND(AVG(valor_compra) FILTER (WHERE fraude = 0), 2)            AS ticket_medio_legitima
FROM abt_fraude;


-- =====================================================================
-- 2. ONDE A FRAUDE SE CONCENTRA
-- =====================================================================

-- 2.1 Faixa de valor da compra.
-- Resultado: a taxa sobe de forma consistente com o valor: 4,2% abaixo de R$ 10,
-- 12,7% entre R$ 250 e 500, e 15,0% acima de R$ 500 (~3,5x).
-- Compras >= R$ 250 são só 2,6% das transações, mas concentram 49% do valor fraudado.
WITH faixas AS (
    SELECT
        CASE
            WHEN valor_compra <  10 THEN '1. < R$10'
            WHEN valor_compra <  25 THEN '2. R$10-25'
            WHEN valor_compra <  50 THEN '3. R$25-50'
            WHEN valor_compra < 100 THEN '4. R$50-100'
            WHEN valor_compra < 250 THEN '5. R$100-250'
            WHEN valor_compra < 500 THEN '6. R$250-500'
            ELSE                         '7. R$500+'
        END AS faixa_valor,
        valor_compra,
        fraude
    FROM abt_fraude
)
SELECT
    faixa_valor,
    COUNT(*)                                                    AS transacoes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_transacoes,
    SUM(fraude)                                                 AS fraudes,
    ROUND(AVG(fraude) * 100, 2)                                 AS taxa_fraude_pct,
    ROUND(SUM(valor_compra) FILTER (WHERE fraude = 1), 0)       AS valor_fraude,
    ROUND(100.0 * SUM(valor_compra) FILTER (WHERE fraude = 1)
          / SUM(SUM(valor_compra) FILTER (WHERE fraude = 1)) OVER (), 1) AS pct_valor_fraude
FROM faixas
GROUP BY faixa_valor
ORDER BY faixa_valor;


-- 2.2 Documentos entregues (cada coluna em um formato: 1/0, 'Y'/'N'/NULL, 'Y'/'N').
-- Resultado: o sinal mais forte da base.
--   doc_1 não entregue: 16,1% de fraude vs 3,8% quando entregue (~4x)
--   doc_2 = 'N':        21,8% vs 6,5% ('Y') e 2,0% (NULL: provavelmente o documento não foi solicitado)
--   doc_3 = 'N':         7,6% vs 2,9%
SELECT 'entrega_doc_1' AS documento, CAST(entrega_doc_1 AS VARCHAR) AS valor,
       COUNT(*) AS transacoes, ROUND(AVG(fraude) * 100, 2) AS taxa_fraude_pct
FROM abt_fraude GROUP BY 1, 2
UNION ALL
SELECT 'entrega_doc_2', COALESCE(entrega_doc_2, 'NULL'),
       COUNT(*), ROUND(AVG(fraude) * 100, 2)
FROM abt_fraude GROUP BY 1, 2
UNION ALL
SELECT 'entrega_doc_3', entrega_doc_3,
       COUNT(*), ROUND(AVG(fraude) * 100, 2)
FROM abt_fraude GROUP BY 1, 2
ORDER BY documento, valor;


-- 2.3 Flag "documentação pendente" = doc_1 não entregue OU doc_2 recusado ('N').
-- COALESCE no doc_2 para que o NULL não "contamine" o OR (NULL OR FALSE = NULL).
-- Resultado: 18% das transações, 16,3% de fraude (vs 2,5%), 62% do valor fraudado.
SELECT
    (entrega_doc_1 = 0 OR COALESCE(entrega_doc_2, '') = 'N')    AS doc_pendente,
    COUNT(*)                                                    AS transacoes,
    SUM(fraude)                                                 AS fraudes,
    ROUND(AVG(fraude) * 100, 2)                                 AS taxa_fraude_pct,
    ROUND(100.0 * SUM(valor_compra) FILTER (WHERE fraude = 1)
          / SUM(SUM(valor_compra) FILTER (WHERE fraude = 1)) OVER (), 1) AS pct_valor_fraude
FROM abt_fraude
GROUP BY 1;


-- 2.4 Hora da compra.
-- Resultado: madrugada (0h-4h) tem 12,3% de fraude vs 4,8% no resto do dia (pico às 2h, 17%).
-- O volume é pequeno (3% das transações): bom candidato a feature, não a regra isolada.
SELECT
    HOUR(data_compra)               AS hora,
    COUNT(*)                        AS transacoes,
    ROUND(AVG(fraude) * 100, 2)     AS taxa_fraude_pct
FROM abt_fraude
GROUP BY 1
ORDER BY 1;


-- 2.5 País (com nome via dim_paises) e piso de volume de 1.000 transações.
-- Sem o piso, Equador (2 fraudes em 4) e Alemanha (3 em 9) "lideram", o que é ruído.
-- Resultado: entre países relevantes, Brasil 5,5% > Argentina 3,7% > EUA 3,1% > Uruguai 1,0%.
-- O Brasil concentra 74% das transações e 82% das fraudes.
-- Obs.: 194 transações têm país NULL (problema de cadastro).
SELECT
    COALESCE(p.nome_pais, '(sem país)')                         AS pais,
    COUNT(*)                                                    AS transacoes,
    SUM(a.fraude)                                               AS fraudes,
    ROUND(AVG(a.fraude) * 100, 2)                               AS taxa_fraude_pct,
    ROUND(100.0 * SUM(a.fraude) / SUM(SUM(a.fraude)) OVER (), 1) AS pct_das_fraudes
FROM abt_fraude AS a
LEFT JOIN dim_paises AS p ON p.sigla_pais = a.pais
GROUP BY 1
HAVING COUNT(*) >= 1000
ORDER BY taxa_fraude_pct DESC;


-- 2.6 Departamento e nível de risco cadastrado da categoria (dim_categorias).
-- Resultado: a variação é pequena (4,3% a 6,1%). Automotivo é o mais alto (6,1%) e
-- o maior em valor fraudado (R$ 153 mil).
-- O "nivel_risco_categoria" do cadastro NÃO discrimina: alto 5,1%, médio 5,2%, baixo 4,7%.
-- Regras baseadas nesse cadastro hoje não têm efeito.
SELECT
    d.departamento,
    COUNT(*)                                                AS transacoes,
    ROUND(AVG(a.fraude) * 100, 2)                           AS taxa_fraude_pct,
    ROUND(SUM(a.valor_compra) FILTER (WHERE a.fraude = 1), 0) AS valor_fraude
FROM abt_fraude AS a
JOIN dim_categorias AS d ON d.id_categoria = a.categoria_produto
GROUP BY 1
ORDER BY taxa_fraude_pct DESC;

SELECT
    d.nivel_risco_categoria,
    COUNT(*)                        AS transacoes,
    ROUND(AVG(a.fraude) * 100, 2)   AS taxa_fraude_pct
FROM abt_fraude AS a
JOIN dim_categorias AS d ON d.id_categoria = a.categoria_produto
GROUP BY 1
ORDER BY 1;


-- 2.7 Canal de venda (não está na ABT, então voltamos à base bruta com o mesmo filtro).
-- Resultado: todos os canais entre 4,9% e 5,1%. Canal é ruído, não vale investir em regra por canal.
SELECT
    t.canal_venda,
    COUNT(*)                        AS transacoes,
    ROUND(AVG(s.fraude) * 100, 2)   AS taxa_fraude_pct
FROM transacoes AS t
JOIN scores_modelo AS s ON s.id_transacao = t.id_transacao
WHERE t.is_teste = 0
GROUP BY 1
ORDER BY taxa_fraude_pct DESC;


-- =====================================================================
-- 3. O SCORE ATUAL (score_fraude_modelo, 0-100) ORDENA O RISCO?
-- =====================================================================

-- 3.1 Taxa de fraude por decil de score (decil 1 = score mais baixo).
-- Se o score funcionasse, a taxa subiria a cada decil. NÃO é o que acontece:
--   decis 1-3 (score 0-28):  2,8% / 4,6% / 3,3%
--   decis 4-7 (score 28-68): 0,3% / 0,6% / 1,3% / 2,0%   <- mais "seguros" que os decis 1-3
--   decis 8-10 (score 68+):  5,2% / 8,6% / 21,4%
-- O score tem formato de "U": a faixa mais baixa esconde 21% de todas as fraudes.
-- Só o decil 10 (score >= 88) é confiável: 21% de fraude, 43% de todas as fraudes.
WITH decis AS (
    SELECT *, NTILE(10) OVER (ORDER BY score_fraude_modelo) AS decil
    FROM abt_fraude
)
SELECT
    decil,
    MIN(score_fraude_modelo)                        AS score_min,
    MAX(score_fraude_modelo)                        AS score_max,
    COUNT(*)                                        AS transacoes,
    SUM(fraude)                                     AS fraudes,
    ROUND(AVG(fraude) * 100, 2)                     AS taxa_fraude_pct,
    ROUND(100.0 * SUM(fraude) / SUM(SUM(fraude)) OVER (), 1) AS pct_das_fraudes
FROM decis
GROUP BY decil
ORDER BY decil;


-- 3.2 Corte atual do modelo (threshold_decisao = 0,5, ou seja score >= 50).
-- Resultado: o corte alerta 48,5% de TODAS as transações com precisão de 7,9%
-- (de cada 100 alertas, 92 são clientes legítimos), e mesmo assim deixa passar 24% das fraudes.
-- Do jeito que está, o score não é operável.
SELECT
    ROUND(100.0 * COUNT(*) FILTER (WHERE score_fraude_modelo >= 50) / COUNT(*), 1)   AS pct_base_alertada,
    ROUND(100.0 * SUM(fraude) FILTER (WHERE score_fraude_modelo >= 50)
          / COUNT(*) FILTER (WHERE score_fraude_modelo >= 50), 1)                     AS precisao_pct,
    ROUND(100.0 * SUM(fraude) FILTER (WHERE score_fraude_modelo >= 50)
          / SUM(fraude), 1)                                                           AS recall_pct
FROM abt_fraude;


-- 3.3 AUC do score, calculada em SQL pela estatística de Mann-Whitney:
-- AUC = (soma dos ranks das fraudes - n1(n1+1)/2) / (n1 * n0), com rank médio nos empates.
-- Resultado: AUC = 0,73. Isso parece razoável, mas esconde a inversão na faixa baixa (3.1):
-- por isso uma métrica só não basta.
WITH ranks AS (
    SELECT
        fraude,
        RANK()   OVER (ORDER BY score_fraude_modelo)
          + (COUNT(*) OVER (PARTITION BY score_fraude_modelo) - 1) / 2.0 AS rank_medio
    FROM abt_fraude
),
n AS (
    SELECT SUM(fraude) AS n1, COUNT(*) - SUM(fraude) AS n0 FROM abt_fraude
)
SELECT
    ROUND((SUM(r.rank_medio) FILTER (WHERE r.fraude = 1) - ANY_VALUE(n.n1) * (ANY_VALUE(n.n1) + 1) / 2.0)
          / (ANY_VALUE(n.n1) * ANY_VALUE(n.n0)), 3) AS auc
FROM ranks AS r
CROSS JOIN n;


-- 3.4 Quem são as fraudes que o score deixa passar (score < 30)?
-- Resultado: elas têm o mesmo perfil das fraudes bem pontuadas (ticket ~1,6x o das legítimas,
-- documentação recusada 3x mais frequente). O modelo não está usando bem esses sinais.
SELECT
    CASE WHEN score_fraude_modelo < 30 THEN '1. baixo (<30)'
         WHEN score_fraude_modelo < 70 THEN '2. médio (30-69)'
         ELSE                               '3. alto (70+)' END        AS faixa_score,
    fraude,
    COUNT(*)                                                            AS transacoes,
    ROUND(AVG(valor_compra), 1)                                         AS ticket_medio,
    ROUND(100 * AVG(CASE WHEN COALESCE(entrega_doc_2, '') = 'N' THEN 1 ELSE 0 END), 1) AS pct_doc2_recusado
FROM abt_fraude
GROUP BY 1, 2
ORDER BY 1, 2;


-- =====================================================================
-- 4. SIMULAÇÃO DA RECOMENDAÇÃO
-- =====================================================================

-- 4.1 Cruzamento valor alto (>= R$ 250) x documentação pendente.
-- Resultado: o segmento "valor alto + doc pendente" tem 888 transações (0,6% da base),
-- 38% de fraude (7,6x a média) e R$ 174 mil fraudados, ou seja 32% de todo o valor perdido.
SELECT
    valor_compra >= 250                                         AS valor_alto,
    (entrega_doc_1 = 0 OR COALESCE(entrega_doc_2, '') = 'N')    AS doc_pendente,
    COUNT(*)                                                    AS transacoes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_base,
    SUM(fraude)                                                 AS fraudes,
    ROUND(AVG(fraude) * 100, 2)                                 AS taxa_fraude_pct,
    ROUND(SUM(valor_compra) FILTER (WHERE fraude = 1), 0)       AS valor_fraude,
    ROUND(100.0 * SUM(valor_compra) FILTER (WHERE fraude = 1)
          / SUM(SUM(valor_compra) FILTER (WHERE fraude = 1)) OVER (), 1) AS pct_valor_fraude
FROM abt_fraude
GROUP BY 1, 2
ORDER BY 1, 2;


-- 4.2 Fila de revisão manual proposta:
--     (valor >= R$ 250 E documentação pendente) OU score >= 88 (decil 10, a faixa em que o score é confiável)
-- Resultado: revisa 10,9% das transações e captura 46% das fraudes e 59% do valor fraudado,
-- com 21% de acerto (2,7x a precisão do corte atual, alertando 4,5x menos transações).
WITH base AS (
    SELECT
        *,
        (valor_compra >= 250
            AND (entrega_doc_1 = 0 OR COALESCE(entrega_doc_2, '') = 'N'))
        OR score_fraude_modelo >= 88                            AS vai_para_revisao
    FROM abt_fraude
)
SELECT
    vai_para_revisao,
    COUNT(*)                                                    AS transacoes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_base,
    SUM(fraude)                                                 AS fraudes,
    ROUND(100.0 * SUM(fraude) / SUM(SUM(fraude)) OVER (), 1)    AS pct_das_fraudes,
    ROUND(AVG(fraude) * 100, 2)                                 AS taxa_fraude_pct,
    ROUND(100.0 * SUM(valor_compra) FILTER (WHERE fraude = 1)
          / SUM(SUM(valor_compra) FILTER (WHERE fraude = 1)) OVER (), 1) AS pct_valor_fraude
FROM base
GROUP BY 1
ORDER BY 1 DESC;
