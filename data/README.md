# Dados

Os arquivos CSV **não são versionados** neste repositório: fazem parte do material do curso.
Para rodar o projeto, coloque os 6 arquivos abaixo em `data/raw/`.

| arquivo | grão | linhas | chave | colunas |
|---|---|---|---|---|
| `transacoes.csv` | 1 por transação | 150.200 | `id_transacao` | id_transacao, data_compra, valor_compra, pais, produto, categoria_produto, entrega_doc_1, entrega_doc_2, entrega_doc_3, canal_venda, is_teste, versao_api |
| `scores_comportamentais.csv` | 1 por transação | 150.200 | `id_transacao` | id_transacao, score_1, score_2, score_4, score_5, score_7, dt_calculo_score, versao_modelo_comportamental |
| `scores_financeiros.csv` | 1 por transação | 150.200 | `id_transacao` | id_transacao, score_3, score_6, score_9, score_10, moeda_calculo, recalculado |
| `scores_modelo.csv` | 1 por transação | 150.200 | `id_transacao` | id_transacao, score_8, score_fraude_modelo, fraude, experimento, threshold_decisao |
| `dim_paises.csv` | 1 por país | 57 | `sigla_pais` | sigla_pais, nome_pais, regiao, moeda_local, locale, ativo |
| `dim_categorias.csv` | 1 por categoria | 8.374 | `id_categoria` | id_categoria, departamento, nivel_risco_categoria, requer_doc_adicional, ativo |

## Observações de qualidade
- `is_teste = 1` em 200 transações (QA): excluídas da ABT.
- `entrega_doc_1` está como 1/0, `entrega_doc_2` como `'Y'`/`'N'`/NULL (~73% nulos) e `entrega_doc_3` como `'Y'`/`'N'`.
- `score_1` … `score_10` são features anonimizadas, com valores nulos em parte das linhas (na ABT, 13.303 das 150.000 transações têm ao menos um score nulo).
- 194 transações têm `pais` nulo.
- Ligações com as dimensões: `transacoes.pais` → `dim_paises.sigla_pais`, `transacoes.categoria_produto` → `dim_categorias.id_categoria`.
