# Camada Analytics – Projeto de Análise de Dados

## 1. Sobre o Projeto

Este projeto tem como objetivo desenvolver uma solução completa de análise de dados, desde a ingestão de arquivos CSV compactados até a disponibilização de informações estruturadas para análises de negócio.

Os arquivos foram processados por meio de scripts Python e carregados no PostgreSQL, onde foram desenvolvidas as camadas Staging e Analytics.

A camada Analytics foi construída para consolidar dados, aplicar regras de negócio, calcular indicadores e disponibilizar estruturas analíticas para consumo no Power BI.

**Tecnologias utilizadas:**
- Python
- PostgreSQL
- SQL
- Power BI
- Machine Learning

---

## 2. Arquitetura do Projeto

O fluxo de dados foi organizado nas seguintes etapas:

1. Recebimento dos arquivos CSV compactados em ZIP.
2. Extração e processamento dos arquivos utilizando Python.
3. Carregamento dos dados no PostgreSQL.
4. Organização dos dados na camada Staging.
5. Transformação e modelagem na camada Analytics.
6. Construção de tabelas fato e dimensão.
7. Integração com resultados de modelos desenvolvidos em Python.
8. Consumo dos dados pelo Power BI.

### Fluxo da arquitetura

```text
Arquivos CSV (ZIP)
        |
        v
Scripts Python
        |
        v
PostgreSQL
        |
        v
Camada Staging
        |
        v
Camada Analytics
        |
        +----------------------+
        |                      |
        v                      v
   Views Analíticas      Modelo Dimensional
                               |
                       +-------+-------+
                       |               |
                       v               v
                   Dimensões        Fatos
                       |               |
                       +-------+-------+
                               |
                               v
                            Power BI

       Modelos Python de Machine Learning
                       |
              +--------+--------+
              |                 |
              v                 v
       Previsão de Demanda   Recomendação
              |                 |
              +--------+--------+
                       |
                       v
                Camada Analytics
```

---

## 3. Construção da Camada Analytics

A camada Analytics foi criada no PostgreSQL por meio do schema `analytics`.

Seu objetivo é transformar os dados da camada Staging em informações preparadas para análises comerciais, financeiras e operacionais.

Inicialmente, foram desenvolvidas views para consolidar informações de:

- Pedidos e itens.
- Clientes.
- Produtos e variantes.
- Categorias.
- Marcas.

### 3.1. View de Vendas

Durante a exploração dos dados, foi desenvolvida a view `analytics.vendas`, consolidando as principais informações comerciais.

A estrutura disponibiliza:

- Identificação de pedidos e itens.
- Data e canal de venda.
- Cliente e produto.
- Categoria e marca.
- Quantidade e preço unitário.
- Valor bruto dos itens.
- Descontos rateados.
- Receita líquida.
- Custo total.
- Lucro por item.

**Regra de negócio:** foram considerados pedidos com status `paid` e `confirmed`.

Os descontos registrados no pedido foram distribuídos proporcionalmente entre os itens, conforme sua participação no subtotal.

Principais cálculos:

```sql
-- Participação do item
valor_bruto_item / subtotal_pedido

-- Desconto rateado
percentual_item * desconto_pedido

-- Receita líquida
valor_bruto_item - desconto_rateado

-- Custo total
quantidade * custo_unitario

-- Lucro
receita_liquida_item - custo_total
```

---

## 4. Validação e Qualidade dos Dados

Durante o desenvolvimento foram realizadas análises para verificar a consistência das informações e compreender as regras de negócio.

Principais validações:

- Comparação entre o total dos pedidos e a soma dos itens.
- Análise da composição da receita e dos descontos.
- Investigação dos status de pedidos, pagamentos e devoluções.
- Reconciliação entre pedidos válidos e pagamentos aprovados.
- Identificação de produtos e variantes sem custo cadastrado.
- Validação do rateio proporcional dos descontos.
- Identificação de divergências financeiras.

Essa etapa foi importante para garantir maior confiabilidade aos indicadores utilizados nas análises.

---

## 5. Modelo Dimensional

Após a exploração e validação dos dados, foram criadas tabelas de dimensão e fato no schema `analytics`, preparando a estrutura para consumo pelo Power BI.

### 5.1. Tabelas de Dimensão

| Dimensão | Descrição |
|---|---|
| `dim_cliente` | Informações cadastrais e características dos clientes. |
| `dim_categoria` | Categorias e hierarquia de produtos. |
| `dim_marca` | Informações das marcas. |
| `dim_produto` | Produtos e suas respectivas variantes/SKUs. |
| `dim_loja` | Lojas e pontos de operação. |
| `dim_vendedor` | Informações dos vendedores. |
| `dim_calendario` | Datas, anos, meses e dias da semana. |

A dimensão `dim_produto` possui granularidade de produto + variante/SKU, permitindo identificar individualmente cada variante comercializada.

A dimensão calendário utiliza a chave `data_key`, no formato `YYYYMMDD`, para facilitar os relacionamentos temporais.

### 5.2. Tabelas Fato

| Tabela | Granularidade | Objetivo |
|---|---|---|
| `fact_vendas` | Um item por pedido | Análise de vendas, quantidades e descontos. |
| `fact_estoque` | Registro de estoque por variante e localização | Controle de disponibilidade e reposição. |
| `fact_devolucoes` | Um item por devolução | Análise de trocas, devoluções e reembolsos. |
| `fact_compras` | Um item por pedido de compra | Análise de compras, fornecedores e custos. |
| `fact_pagamentos` | Um registro por pagamento | Análise de recebimentos e métodos de pagamento. |

As tabelas foram estruturadas para manter a granularidade de cada evento, evitando misturar movimentações distintas em uma mesma fato.

---

## 6. Análises de Negócio Desenvolvidas em SQL

A camada Analytics também serviu de base para explorar diferentes perspectivas do negócio.

### 6.1. Produtos e Lucratividade

Foram desenvolvidas análises para identificar:

- Produtos com prejuízo.
- Produtos com menor margem.
- Produtos mais lucrativos.
- Participação dos produtos no lucro total.
- Concentração do lucro nos Top 10 e Top 20 produtos.

### 6.2. Análises Temporais

Foram desenvolvidas consultas para investigar:

- Faturamento mensal e anual.
- Ticket médio.
- Crescimento anual (YoY).
- Vendas por dia da semana.
- Dias com e sem vendas.
- Sazonalidade por mês do ano.

Também foi utilizado `generate_series()` para construir um calendário diário e considerar dias sem vendas no cálculo das médias.

### 6.3. Análise de Clientes

Foram realizadas análises de:

- Faturamento por cliente.
- Quantidade de pedidos.
- Ticket médio.
- Concentração de receita nos principais clientes.
- Participação dos Top 10, Top 20, Top 50 e Top 100 clientes.

### 6.4. Segmentação RFM

Foi desenvolvida uma segmentação de clientes utilizando a metodologia RFM:

- **Recência:** tempo desde a última compra.
- **Frequência:** quantidade de compras realizadas.
- **Valor Monetário:** faturamento acumulado por cliente.

Foram calculados scores de 1 a 5 para cada dimensão, utilizando `NTILE()` no PostgreSQL.

Os clientes foram classificados em segmentos como:

- Campeões / VIP.
- Clientes fiéis.
- Alto valor em risco.
- Clientes em risco.
- Clientes recentes.
- Inativos / baixo valor.
- Clientes intermediários.

---

## 7. Integração com Machine Learning

Além das análises tradicionais, foram criadas estruturas para armazenar resultados de modelos desenvolvidos em Python.

### 7.1. Previsão de Demanda

Tabela: `analytics.previsao_bussola_702`

Armazena os resultados do modelo de previsão de demanda.

Principais campos:

- `mes`
- `venda_real`
- `previsao`
- `erro_absoluto`
- `mae`

Permite comparar os valores previstos com os realizados e acompanhar o desempenho do modelo.

### 7.2. Sistema de Recomendação de Produtos

Tabela: `analytics.recomendacoes_produtos`

Armazena os resultados do sistema de recomendação desenvolvido em Python.

Principais campos:

- `produto_referencia_id`
- `produto_referencia`
- `produto_recomendado_id`
- `produto_recomendado`
- `similaridade`
- `ranking`

Essa estrutura permite identificar produtos semelhantes e disponibilizar recomendações para análises comerciais.

---

## 8. Integração com Power BI

Após a construção das tabelas fato e dimensão, a camada Analytics foi preparada para consumo pelo Power BI.

A proposta é utilizar o modelo dimensional como base para construção de dashboards e indicadores, mantendo as principais transformações e regras de negócio centralizadas no PostgreSQL.

**Principais possibilidades de análise:**

- **Comercial:** faturamento, vendas, ticket médio e desempenho por canal.
- **Financeira:** receita líquida, custos, lucro, margem e pagamentos.
- **Produtos:** desempenho por produto, categoria e marca.
- **Clientes:** faturamento, concentração de receita e segmentação RFM.
- **Estoque:** disponibilidade e pontos de reposição.
- **Devoluções:** motivos, quantidades e valores reembolsados.
- **Compras:** volumes adquiridos, custos e fornecedores.
- **Inteligência de dados:** previsão de demanda e recomendação de produtos.

---

## 9. Tecnologias Utilizadas

| Tecnologia | Aplicação |
|---|---|
| Python | Extração, processamento e carga dos arquivos CSV. |
| PostgreSQL | Armazenamento, transformação e modelagem dos dados. |
| SQL | Construção das views, fatos, dimensões e análises. |
| DBeaver | Ferramenta utilizada para conexão, gerenciamento e execução de scripts SQL no banco de dados. |
| Power BI | Visualização de dados e construção de dashboards. |
| Machine Learning | Previsão de demanda e recomendação de produtos. |

---

## 10. Conclusão

A construção da camada Analytics representou uma etapa fundamental para transformar os dados brutos em informações estruturadas e preparadas para apoiar decisões de negócio.

O projeto envolveu desde a ingestão dos arquivos e organização dos dados até a aplicação de regras de negócio, validações financeiras, construção de um modelo dimensional e integração com soluções de Business Intelligence e Machine Learning.

**O objetivo foi desenvolver um fluxo completo de dados, conectando Engenharia de Dados, Análise de Dados, Business Intelligence e Ciência de Dados para transformar informações em conhecimento e apoiar decisões estratégicas.**


---
### 🚀 Projetos e Portfólio
Desenvolvo projetos práticos envolvendo análise de dados, dashboards, indicadores de desempenho, ETL e visualização analítica, conectando tecnologia e problemas reais de negócio.

- 📊 [Portfólio com análises no Medium](https://medium.com/@maironhenrique)
- 📈 [Portfólio com Dashboards](https://app.xperiun.com/in/maironhenrique)
---
### 📫 Contato
**E-mail**: maironhenrique@hotmail.com  
**LinkedIn**: https://www.linkedin.com/in/maironhenriquedeoliveira

#### <p align="left"> <code>Transformando dados em insights para decisões melhores.</code></p>
