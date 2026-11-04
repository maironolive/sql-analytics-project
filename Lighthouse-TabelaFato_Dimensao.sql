--CRIANDO AS TABELAS DIMENSÕES E FATOS NO SCHEMA ANALYTICS

--=======================================================
--DIMENSÃO CLIENTES
--=======================================================
-- Cria a dimensão de clientes para análises comerciais.
DROP TABLE IF EXISTS analytics.dim_cliente;

CREATE TABLE analytics.dim_cliente AS
SELECT
    id AS customer_id,
    person_type,
    legal_name,
    trade_name,
    tax_id,
    email,
    phone,
    is_active,
    created_at,
    updated_at
FROM staging.customers;

-- Define a chave primária da dimensão cliente.
ALTER TABLE analytics.dim_cliente
ADD CONSTRAINT pk_dim_cliente
PRIMARY KEY (customer_id);

--=======================================================
--DIMENSÃO CATEGORIA
--=======================================================
-- Cria a dimensão de categorias de produtos.
DROP TABLE IF EXISTS analytics.dim_categoria;

CREATE TABLE analytics.dim_categoria AS
SELECT
    id AS category_id,
    name AS category_name,
    slug,
    parent_category_id,
    is_active,
    created_at,
    updated_at
FROM staging.categories;

-- Define a chave primária da dimensão categoria.
ALTER TABLE analytics.dim_categoria
ADD CONSTRAINT pk_dim_categoria
PRIMARY KEY (category_id);

--=======================================================
--DIMENSÃO MARCA
--=======================================================
-- Cria a dimensão de marcas dos produtos.
DROP TABLE IF EXISTS analytics.dim_marca;

CREATE TABLE analytics.dim_marca AS
SELECT
    id AS brand_id,
    name AS brand_name,
    country,
    is_active,
    created_at,
    updated_at
FROM staging.brands;

-- Define a chave primária da dimensão marca.
ALTER TABLE analytics.dim_marca
ADD CONSTRAINT pk_dim_marca
PRIMARY KEY (brand_id);


--=======================================================
--DIMENSÃO PRODUTO
--=======================================================
-- Cria a dimensão de produtos consolidando produto e suas variantes.
DROP TABLE IF EXISTS analytics.dim_produto;

CREATE TABLE analytics.dim_produto AS
SELECT
    p.id AS product_id,
    p.name AS product_name,
    p.description,
    p.brand_id,
    b.name AS brand_name,
    p.category_id,
    c.name AS category_name,
    p.ncm_code,
    p.unit_of_measure,
    p.is_active AS product_is_active,
    pv.id AS product_variant_id,
    pv.sku,
    pv.barcode_ean,
    pv.sale_price,
    pv.cost_price,
    pv.weight_kg,
    pv.is_active AS variant_is_active
FROM staging.products AS p
LEFT JOIN staging.brands AS b
    ON b.id = p.brand_id
LEFT JOIN staging.categories AS c
    ON c.id = p.category_id
LEFT JOIN staging.product_variants AS pv
    ON pv.product_id = p.id;
--===============================================================================
--Aqui existe uma característica importante:
--
--Um produto pode possuir várias variantes.
--
--Portanto, dim_produto poderá possuir mais de uma linha para o mesmo product_id.
--
--Isso é aceitável se o grão da dimensão for produto + variante.
--
--Vamos deixar isso explícito:
--===============================================================================
-- A dimensão trabalha no nível de produto + variante/SKU.
ALTER TABLE analytics.dim_produto
ADD CONSTRAINT pk_dim_produto
PRIMARY KEY (product_variant_id);

--=======================================================
--DIMENSÃO LOJA
--=======================================================
-- Cria a dimensão de lojas e demais pontos de operação.
DROP TABLE IF EXISTS analytics.dim_loja;

CREATE TABLE analytics.dim_loja AS
SELECT
    id AS location_id,
    name AS location_name,
    location_type,
    postal_code,
    city,
    state,
    country,
    is_active,
    created_at,
    updated_at
FROM staging.locations;

-- Define a chave primária da dimensão localização.
ALTER TABLE analytics.dim_loja
ADD CONSTRAINT pk_dim_loja
PRIMARY KEY (location_id);

--=======================================================
--DIMENSÃO VENDEDOR
--=======================================================
-- Cria a dimensão dos vendedores responsáveis pelas vendas.
DROP TABLE IF EXISTS analytics.dim_vendedor;

CREATE TABLE analytics.dim_vendedor AS
SELECT
    id AS salesperson_id,
    full_name,
    role,
    primary_location_id,
    hire_date,
    termination_date,
    is_active
FROM staging.employees;

-- Define a chave primária da dimensão vendedor.
ALTER TABLE analytics.dim_vendedor
ADD CONSTRAINT pk_dim_vendedor
PRIMARY KEY (salesperson_id);


--=======================================================
--DIMENSÃO CALENDÁRIO
--=======================================================
-- Cria a dimensão calendário no modelo analítico.
DROP TABLE IF EXISTS analytics.dim_calendario;

CREATE TABLE analytics.dim_calendario AS
SELECT
    data,
    ano,
    mes,
    dia,
    dia_semana_numero,
    dia_semana
FROM lighthouse.dim_calendario;

-- Cria uma chave substituta para relacionamento com as tabelas fato.
ALTER TABLE analytics.dim_calendario
ADD COLUMN data_key INTEGER;

-- Preenche a chave no formato YYYYMMDD.
UPDATE analytics.dim_calendario
SET data_key =
      EXTRACT(YEAR FROM data)::INTEGER * 10000
    + EXTRACT(MONTH FROM data)::INTEGER * 100
    + EXTRACT(DAY FROM data)::INTEGER;

-- Define a chave primária da dimensão.
ALTER TABLE analytics.dim_calendario
ADD CONSTRAINT pk_dim_calendario
PRIMARY KEY (data_key);

-- Garante que não existam duas linhas para a mesma data.
CREATE UNIQUE INDEX uq_dim_calendario_data
ON analytics.dim_calendario (data);


--=======================================================
--FATOS 
--=======================================================

--=======================================================
-- FATO VENDAS
--=======================================================
-- Objetivo:
-- Disponibilizar os itens vendidos para análises comerciais
-- de faturamento, descontos, quantidade, produtos e clientes.
--
-- Grão:
-- 1 linha = 1 item de um pedido de venda.
--
-- Tabelas utilizadas:
-- staging.orders
-- staging.order_items
-- staging.product_variants
-- staging.products
--
-- Os valores permanecem na granularidade do item.
-- Métricas agregadas serão calculadas posteriormente no Power BI.
--=======================================================

DROP TABLE IF EXISTS analytics.fact_vendas;

CREATE TABLE analytics.fact_vendas AS
WITH itens AS (
    SELECT
        --===================================================
        -- CHAVES DO PEDIDO E DO ITEM
        --===================================================
        o.id AS order_id,
        oi.id AS order_item_id,
        --===================================================
        -- CHAVES DAS DIMENSÕES
        --===================================================
        o.customer_id,
        o.salesperson_id,
        o.location_id,
        pv.product_id,
        oi.product_variant_id,
        p.category_id,
        p.brand_id,
        --===================================================
        -- DATA
        --===================================================
        o.placed_at::date AS data,
        --===================================================
        -- INFORMAÇÕES DO PEDIDO
        --===================================================
        o.order_number,
        o.channel,
        o.status,
        --===================================================
        -- INFORMAÇÕES DO ITEM
        --===================================================
        oi.quantity AS quantidade,
        oi.unit_price AS preco_unitario,
        oi.line_total AS valor_item,
        --===================================================
        -- DESCONTO DO PEDIDO
        --===================================================
        COALESCE(o.discount_amount, 0) AS desconto_pedido,
        -- Soma dos itens para realizar o rateio proporcional
        -- do desconto do pedido.
        SUM(oi.line_total) OVER (
            PARTITION BY o.id
        ) AS subtotal_itens
    FROM staging.orders AS o
    INNER JOIN staging.order_items AS oi
        ON oi.order_id = o.id
    INNER JOIN staging.product_variants AS pv
        ON pv.id = oi.product_variant_id
    INNER JOIN staging.products AS p
        ON p.id = pv.product_id
)
SELECT
    --===================================================
    -- CHAVES
    --===================================================
    order_id,
    order_item_id,
    --===================================================
    -- DIMENSÕES
    --===================================================
    customer_id,
    salesperson_id,
    location_id,
    product_id,
    product_variant_id,
    category_id,
    brand_id,
    --===================================================
    -- DATA
    --===================================================
    data,
    --===================================================
    -- INFORMAÇÕES DO PEDIDO
    --===================================================
    order_number,
    channel,
    status,
    --===================================================
    -- MÉTRICAS NO NÍVEL DO ITEM
    --===================================================
    quantidade,
    preco_unitario,
    valor_item,
    --===================================================
    -- DESCONTO RATEADO POR ITEM
    --===================================================
    CASE
        WHEN subtotal_itens > 0
        THEN desconto_pedido * (valor_item / subtotal_itens)
        ELSE 0
    END AS desconto_item
FROM itens;

--=======================================================
-- CHAVE PRIMÁRIA
--=======================================================
-- O grão da fato é 1 linha por item do pedido.

ALTER TABLE analytics.fact_vendas
ADD CONSTRAINT pk_fact_vendas
PRIMARY KEY (order_item_id);



--=======================================================
--FATO ESTOQUE
--=======================================================
DROP TABLE IF EXISTS analytics.fact_estoque;

CREATE TABLE analytics.fact_estoque AS
SELECT
    -- Chaves para relacionamento com as dimensões.
    sl.product_variant_id,
    sl.location_id,
    -- Métricas de estoque.
    sl.quantity_on_hand AS quantidade_estoque,
    sl.reorder_point AS ponto_reposicao,
    -- Data da atualização do estoque.
    sl.updated_at::date AS data_atualizacao,
    -- Chave da dimensão calendário.
    (
        EXTRACT(YEAR FROM sl.updated_at)::integer * 10000
        +
        EXTRACT(MONTH FROM sl.updated_at)::integer * 100
        +
        EXTRACT(DAY FROM sl.updated_at)::integer
    ) AS data_key
FROM staging.stock_levels AS sl;


--=======================================================
-- FATO DEVOLUÇÕES
--=======================================================
-- Objetivo:
-- Disponibilizar os eventos de devolução em granularidade
-- de item para análises comerciais.
--
-- Grão:
-- 1 linha = 1 item de uma devolução.
--
-- Tabelas utilizadas:
-- staging.returns
-- staging.return_items
-- staging.order_items
-- staging.product_variants
-- staging.products
--
-- A fato mantém tanto devoluções com reembolso (refund)
-- quanto trocas (exchange).
--
-- Os valores permanecem na granularidade do item.
-- Agregações e indicadores comerciais serão calculados
-- posteriormente no Power BI por meio de medidas DAX.
--=======================================================

DROP TABLE IF EXISTS analytics.fact_devolucoes;

CREATE TABLE analytics.fact_devolucoes AS
SELECT
    --===================================================
    -- CHAVES DA DEVOLUÇÃO
    --===================================================
    r.id AS return_id,
    ri.id AS return_item_id,
    -- Pedido original
    r.order_id,
    -- Item do pedido originalmente vendido
    ri.order_item_id,
    --===================================================
    -- CHAVES DAS DIMENSÕES
    --===================================================
    r.customer_id,
    pv.product_id,
    oi.product_variant_id,
    p.category_id,
    p.brand_id,
    -- Localização onde a devolução foi registrada/recebida
    r.received_at_location_id AS location_id,
    --===================================================
    -- DATA
    --===================================================
    -- Data de criação do registro da devolução.
    -- Será utilizada para relacionamento com dim_calendario.
    r.created_at::date AS data,
    --===================================================
    -- INFORMAÇÕES DA DEVOLUÇÃO
    --===================================================
    r.return_number,
    r.status AS return_status,
    r.reason,
    --===================================================
    -- INFORMAÇÕES DO ITEM DEVOLVIDO
    --===================================================
    -- Tipo de tratamento da devolução:
    -- refund   = reembolso
    -- exchange = troca
    ri.action,
    -- Quantidade efetivamente devolvida
    ri.quantity AS quantidade_devolvida,
    -- Variante recebida em caso de troca
    ri.exchange_variant_id,
    -- Valor unitário utilizado no reembolso
    ri.unit_refund_amount AS valor_reembolso_unitario,
    -- Valor de reembolso correspondente ao item.
    -- Para trocas, normalmente será zero.
    ri.quantity * ri.unit_refund_amount AS valor_reembolso
FROM staging.returns AS r
-- Relaciona cada devolução aos seus itens
INNER JOIN staging.return_items AS ri
    ON ri.return_id = r.id
-- Recupera o item originalmente vendido
INNER JOIN staging.order_items AS oi
    ON oi.id = ri.order_item_id
-- Recupera o produto associado à variante
INNER JOIN staging.product_variants AS pv
    ON pv.id = oi.product_variant_id
-- Recupera categoria e marca do produto
INNER JOIN staging.products AS p
    ON p.id = pv.product_id;

--=======================================================
-- CHAVE PRIMÁRIA
--=======================================================
-- Como o grão da fato é 1 linha por item de devolução,
-- return_item_id identifica unicamente cada registro.

ALTER TABLE analytics.fact_devolucoes
ADD CONSTRAINT pk_fact_devolucoes
PRIMARY KEY (return_item_id);

--=======================================================
-- CHAVE DA DIMENSÃO CALENDÁRIO
--=======================================================
-- Cria a chave no formato YYYYMMDD para relacionamento
-- com analytics.dim_calendario.
ALTER TABLE analytics.fact_devolucoes
ADD COLUMN data_key INTEGER;

UPDATE analytics.fact_devolucoes
SET data_key =
      EXTRACT(YEAR FROM data)::INTEGER * 10000
    + EXTRACT(MONTH FROM data)::INTEGER * 100
    + EXTRACT(DAY FROM data)::INTEGER;


--=======================================================
-- RELACIONAMENTO COM A DIMENSÃO CALENDÁRIO
--=======================================================

ALTER TABLE analytics.fact_devolucoes
ADD CONSTRAINT fk_fact_devolucoes_calendario
FOREIGN KEY (data_key)
REFERENCES analytics.dim_calendario(data_key);


-=======================================================
-- FATO COMPRAS
--=======================================================
-- Objetivo:
-- Disponibilizar os itens de pedidos de compra para análises
-- comerciais relacionadas a compras, fornecedores, produtos,
-- custos e volumes adquiridos.
--
-- Grão:
-- 1 linha = 1 item de pedido de compra.
--
-- Tabelas utilizadas:
-- staging.purchase_orders
-- staging.purchase_order_items
--
-- Os valores permanecem na granularidade do item.
-- Agregações serão realizadas posteriormente no Power BI.
--=======================================================

DROP TABLE IF EXISTS analytics.fact_compras;

CREATE TABLE analytics.fact_compras AS
SELECT
    --===================================================
    -- CHAVES DO PEDIDO DE COMPRA
    --===================================================
    po.id AS purchase_order_id,
    poi.id AS purchase_order_item_id,
    --===================================================
    -- CHAVES DAS DIMENSÕES
    --===================================================
    poi.product_variant_id,
    po.supplier_id,
    po.buyer_id,
    po.destination_location_id AS location_id,
    --===================================================
    -- DATA
    --===================================================
    po.placed_at::date AS data,
    --===================================================
    -- INFORMAÇÕES DO PEDIDO
    --===================================================
    po.po_number,
    po.status,
    po.currency,
    --===================================================
    -- INFORMAÇÕES DO ITEM
    --===================================================
    poi.quantity_ordered AS quantidade,
    poi.unit_cost AS custo_unitario,
    poi.line_total AS valor_item,
    --===================================================
    -- DATA PREVISTA DE ENTREGA
    --===================================================
    po.expected_delivery_at::date AS data_entrega_prevista
FROM staging.purchase_orders AS po
INNER JOIN staging.purchase_order_items AS poi
    ON poi.purchase_order_id = po.id;

--=======================================================
-- CHAVE PRIMÁRIA
--=======================================================
-- O grão da fato é 1 linha por item do pedido de compra.

ALTER TABLE analytics.fact_compras
ADD CONSTRAINT pk_fact_compras
PRIMARY KEY (purchase_order_item_id);

--=======================================================
-- CHAVE DA DIMENSÃO CALENDÁRIO
--=======================================================

ALTER TABLE analytics.fact_compras
ADD COLUMN data_key INTEGER;

UPDATE analytics.fact_compras
SET data_key =
      EXTRACT(YEAR FROM data)::INTEGER * 10000
    + EXTRACT(MONTH FROM data)::INTEGER * 100
    + EXTRACT(DAY FROM data)::INTEGER;

--=======================================================
-- RELACIONAMENTO COM A DIMENSÃO CALENDÁRIO
--=======================================================

ALTER TABLE analytics.fact_compras
ADD CONSTRAINT fk_fact_compras_calendario
FOREIGN KEY (data_key)
REFERENCES analytics.dim_calendario(data_key);



--=======================================================
-- FATO PAGAMENTOS
--=======================================================
-- Objetivo:
-- Disponibilizar os registros de pagamento para análises
-- comerciais relacionadas a recebimentos, aprovação,
-- pendências, recusas e métodos de pagamento.
--
-- Grão:
-- 1 linha = 1 registro de pagamento.
--
-- Tabela utilizada:
-- staging.payments
--
-- Um pedido pode possuir mais de um pagamento.
-- Portanto, os pagamentos permanecem em uma fato própria
-- para evitar duplicação das linhas da fact_vendas.
--=======================================================

DROP TABLE IF EXISTS analytics.fact_pagamentos;

CREATE TABLE analytics.fact_pagamentos AS
SELECT
    --===================================================
    -- CHAVES
    --===================================================
    p.id AS payment_id,
    p.order_id,
    --===================================================
    -- INFORMAÇÕES DO PAGAMENTO
    --===================================================
    p.method,
    p.installments,
    p.status AS payment_status,
    --===================================================
    -- MÉTRICAS NO NÍVEL DO PAGAMENTO
    --===================================================
    p.amount AS valor_pagamento,
    --===================================================
    -- DATAS
    --===================================================
    p.paid_at::date AS data_pagamento,
    p.created_at::date AS data_criacao,
    p.updated_at::date AS data_atualizacao
FROM staging.payments AS p;

--=======================================================
-- CHAVE PRIMÁRIA
--=======================================================
-- Cada registro de pagamento possui seu próprio ID.

ALTER TABLE analytics.fact_pagamentos
ADD CONSTRAINT pk_fact_pagamentos
PRIMARY KEY (payment_id);





--==============================================================
--VALIDAÇÃO DAS TABELAS FATOS
--==============================================================
-- Verificar as duas fatos
--
-- Confirma a estrutura das duas tabelas fato.
SELECT
    table_name,
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'analytics'
  AND table_name IN (
      'fact_vendas',
      'fact_estoque'
  )
ORDER BY
    table_name,
    ordinal_position;

--================================================================
-- Verifica o volume de registros criado em cada fato.
SELECT
    'fact_vendas' AS tabela,
    COUNT(*) AS registros
FROM analytics.fact_vendas
UNION ALL
SELECT
    'fact_estoque' AS tabela,
    COUNT(*) AS registros
FROM analytics.fact_estoque;


--====================================================================================
--Uma validação importante da fact_vendas
--confirmar que não perdemos nenhum item de pedido:

-- Compara a quantidade de itens entre a origem e a fato.
SELECT
    (
        SELECT COUNT(*)
        FROM staging.order_items
    ) AS itens_staging,
    (
        SELECT COUNT(*)
        FROM analytics.fact_vendas
    ) AS itens_fact;

--================================================================
-- Confirma se todas as vendas receberam uma data_key.
SELECT
    COUNT(*) AS total_registros,
    COUNT(data_key) AS registros_com_data_key,
    COUNT(*) - COUNT(data_key) AS registros_sem_data_key
FROM analytics.fact_vendas;

--================================================================
-- Verifica se existem registros de estoque sem data_key.
SELECT
    COUNT(*) AS total_registros,
    COUNT(data_key) AS registros_com_data_key,
    COUNT(*) - COUNT(data_key) AS registros_sem_data_key
FROM analytics.fact_estoque;

--================================================================
-- Identifica vendas cuja data_key não existe na dimensão calendário.
SELECT
    fv.data_key,
    COUNT(*) AS quantidade_registros
FROM analytics.fact_vendas AS fv
LEFT JOIN analytics.dim_calendario AS dc
    ON dc.data_key = fv.data_key
WHERE dc.data_key IS NULL
GROUP BY
    fv.data_key;

--================================================================
-- Confirma que o valor dos itens foi preservado
-- durante a criação da fato.
SELECT
    (
        SELECT SUM(line_total)
        FROM staging.order_items
    ) AS valor_staging,
    (
        SELECT SUM(valor_item)
        FROM analytics.fact_vendas
    ) AS valor_fact,
    (
        SELECT SUM(line_total)
        FROM staging.order_items
    )
    -
    (
        SELECT SUM(valor_item)
        FROM analytics.fact_vendas
    ) AS diferenca;

--================================================================
-- Valida os principais indicadores financeiros adicionados à fato.
SELECT
    COUNT(*) AS total_itens,
    COUNT(custo_unitario) AS itens_com_custo,
    SUM(valor_item) AS faturamento,
    SUM(custo_total) AS custo_total,
    SUM(margem_bruta) AS margem_bruta
FROM analytics.fact_vendas;

--================================================================
-- Amostra os cálculos de receita, custo e margem por item.
SELECT
    product_variant_id,
    quantidade,
    valor_item,
    custo_unitario,
    custo_total,
    margem_bruta
FROM analytics.fact_vendas
LIMIT 20;

--================================================================
-- Confere se a margem está sendo calculada corretamente.
SELECT
    COUNT(*) AS registros_com_diferenca
FROM analytics.fact_vendas
WHERE margem_bruta IS DISTINCT FROM
      (valor_item - custo_total);

--================================================================
-- Valida a quantidade de registros e o estoque disponível.
SELECT
    COUNT(*) AS registros,
    SUM(quantidade_estoque) AS estoque_total,
    SUM(ponto_reposicao) AS pontos_reposicao
FROM analytics.fact_estoque;


--================================================================
-- Verifica se o ponto de reposição possui valores cadastrados.
SELECT
    COUNT(*) AS registros,
    COUNT(ponto_reposicao) AS registros_com_reposicao,
    COUNT(*) - COUNT(ponto_reposicao) AS registros_sem_reposicao,
    SUM(ponto_reposicao) AS total_ponto_reposicao
FROM analytics.fact_estoque;

--================================================================
-- Verifica a disponibilidade do ponto de reposição na tabela de origem.
SELECT
    COUNT(*) AS registros,
    COUNT(reorder_point) AS registros_com_reposicao,
    COUNT(*) - COUNT(reorder_point) AS registros_sem_reposicao,
    SUM(reorder_point) AS total_ponto_reposicao
FROM staging.stock_levels;

--================================================================
-- Confirma se a quantidade de estoque foi preservada durante a carga.
SELECT
    (SELECT SUM(quantity_on_hand)
     FROM staging.stock_levels) AS estoque_staging,
    (SELECT SUM(quantidade_estoque)
     FROM analytics.fact_estoque) AS estoque_analytics,
    (SELECT SUM(quantity_on_hand)
     FROM staging.stock_levels)
    -
    (SELECT SUM(quantidade_estoque)
     FROM analytics.fact_estoque) AS diferenca;

--================================================================
-- Valida os principais indicadores financeiros da fato de vendas.
SELECT
    COUNT(*) AS registros,
    COUNT(DISTINCT order_id) AS pedidos,
    SUM(quantidade) AS quantidade_vendida,
    SUM(valor_item) AS faturamento,
    SUM(custo_total) AS custo_total,
    SUM(margem_bruta) AS margem_bruta
FROM analytics.fact_vendas;


--===============================================================
--CRIANDO TABELAS DE PREVISÃO E SISTEMA DE RECOMENDAÇÃO
--
--Baseado nos script python que foram criados
--===============================================================

--PREVISÃO DE DEMANDA - Bussula 702
-- Armazena os resultados gerados pelo modelo de previsão em Python.
DROP TABLE IF EXISTS analytics.previsao_bussola_702;

CREATE TABLE analytics.previsao_bussola_702 (
    mes DATE,
    venda_real INTEGER,
    previsao NUMERIC(18,2),
    erro_absoluto NUMERIC(18,2),
    mae NUMERIC(18,2)
);


--===================================================================
--RECOMENDAÇÃO DE PRODUTOS
--====================================================================
-- Armazena o ranking produzido pelo modelo de recomendação em Python.
DROP TABLE IF EXISTS analytics.recomendacoes_produtos;

CREATE TABLE analytics.recomendacoes_produtos (
    produto_referencia_id INTEGER,
    produto_referencia VARCHAR(255),
    produto_recomendado_id INTEGER,
    produto_recomendado VARCHAR(255),
    similaridade NUMERIC(10,6),
    ranking INTEGER
);


--================================================================
-- Confirma se os resultados da previsão foram carregados no Analytics.
SELECT
    mes,
    venda_real,
    previsao,
    erro_absoluto,
    mae
FROM analytics.previsao_bussola_702
ORDER BY mes;

--================================================================
-- Confirma a estrutura da tabela que receberá o ranking do recomendador.
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'analytics'
  AND table_name = 'recomendacoes_produtos'
ORDER BY ordinal_position;

--================================================================
-- Valida o ranking que será disponibilizado ao Power BI.
SELECT
    ranking,
    produto_recomendado,
    similaridade
FROM analytics.recomendacoes_produtos
ORDER BY ranking;
