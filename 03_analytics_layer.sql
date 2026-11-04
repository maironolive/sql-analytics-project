-- =====================================================================
--CRIANDO A CAMADA ANALYTICS
-- =====================================================================
--A analytics representa os dados preparados para responder às perguntas do negócio
-- =====================================================================

--Criando o SCHEMA ANALYTICS
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS analytics;

-- =====================================================================
--Criando View para visão analítica sobre VENDAS
-- =====================================================================
CREATE OR REPLACE VIEW analytics.vendas1 AS
SELECT
    o.id AS order_id,
    o.order_number,
    o.placed_at,
    o.customer_id,
    c.person_type,
    o.channel,
    o.status AS order_status,
    oi.id AS order_item_id,
    oi.product_variant_id, 
    pv.product_id,
    p.name AS product_name,
    p.brand_id,
    b.name AS brand_name,
    p.category_id,
    cat.name AS category_name,
    oi.quantity,
    oi.unit_price,
    oi.line_total,
    pv.cost_price,
    oi.quantity * pv.cost_price AS total_cost,
    oi.line_total -
    (oi.quantity * pv.cost_price) AS gross_profit
FROM staging.orders o
INNER JOIN staging.order_items oi
    ON o.id = oi.order_id
INNER JOIN staging.customers c
    ON o.customer_id = c.id
INNER JOIN staging.product_variants pv
    ON oi.product_variant_id = pv.id
INNER JOIN staging.products p
    ON pv.product_id = p.id
LEFT JOIN staging.brands b
    ON p.brand_id = b.id
LEFT JOIN staging.categories cat
    ON p.category_id = cat.id;


-- =====================================================================
--Resultado da View criada
-- =====================================================================
SELECT *
FROM analytics.vendas1
LIMIT 20;

-- =====================================================================
--Total de registros
-- =====================================================================
SELECT
    COUNT(*) AS registros
FROM analytics.vendas;

-- =====================================================================
--Resumo de vendas
-- =====================================================================
SELECT
    MIN(placed_at) AS primeira_venda,
    MAX(placed_at) AS ultima_venda,
    SUM(line_total) AS receita,
    SUM(total_cost) AS custo,
    SUM(gross_profit) AS lucro
FROM analytics.vendas;


-- =====================================================================
--VALIDAÇÃO DOS DADOS
-- =====================================================================

--Valor total registrado nos pedidos
-- =====================================================================
SELECT
    SUM(total) AS receita_pedidos
FROM staging.orders;

--Soma dos itens
SELECT
    SUM(line_total) AS receita_itens
FROM staging.order_items;

-- =====================================================================
--Descobrindo como é formada a receita
-- =====================================================================
SELECT
    SUM(subtotal) AS subtotal,
    SUM(discount_amount) AS descontos,
    SUM(total) AS total
FROM staging.orders;

-- =====================================================================
--descobrindo subtotal
-- =====================================================================
SELECT
    SUM(subtotal - discount_amount) AS total_calculado,
    SUM(total) AS total_pedido,
    SUM((subtotal - discount_amount) - total) AS diferenca
FROM staging.orders;

-- =====================================================================
--Descobrindo Pedidos considerados vendas de acordo com Status em cada uma das tabelas a seguir:
-- =====================================================================

--tabela orders
-- =====================================================================
SELECT
    status,
    COUNT(*) AS quantidade,
    SUM(total) AS valor_total
FROM staging.orders
GROUP BY status
ORDER BY quantidade DESC;

-- =====================================================================
--tabela payments
-- =====================================================================
SELECT
    status,
    COUNT(*) AS quantidade,
    SUM(amount) AS valor_total
FROM staging.payments
GROUP BY status
ORDER BY quantidade DESC;

-- =====================================================================
--tabela returns
-- =====================================================================
SELECT
    status,
    COUNT(*) AS quantidade,
    SUM(total_refund_amount) AS valor_reembolsado
FROM staging.returns
GROUP BY status
ORDER BY quantidade DESC;

-- =====================================================================
--VALIDAÇÃO
--Verificar se a relação entre status do pedido e status financeiro é coerente.
-- =====================================================================

SELECT
    o.status AS order_status,
    p.status AS payment_status,
    COUNT(DISTINCT o.id) AS pedidos,
    SUM(p.amount) AS valor_pagamentos
FROM staging.orders o
LEFT JOIN staging.payments p
    ON o.id = p.order_id
GROUP BY
    o.status,
    p.status
ORDER BY
    o.status,
    p.status;

-- =====================================================================
--reconciliação financeira
-- =====================================================================
--paid, confirmed
-- =====================================================================
SELECT
    SUM(total) AS total_pedidos
FROM staging.orders
WHERE status IN ('paid', 'confirmed');

-- =====================================================================
--approved
-- =====================================================================
SELECT
    SUM(amount) AS total_pagamentos_aprovados
FROM staging.payments
WHERE status = 'approved';

-- =====================================================================
--pid, cnfirmed
-- =====================================================================
SELECT
    SUM(total) AS total_paid_confirmed
FROM staging.orders
WHERE status IN ('paid', 'confirmed');

-- =====================================================================
--entender por que os pagamentos aprovados são menores que os pedidos válidos.
-- =====================================================================
SELECT
    o.status AS order_status,
    p.status AS payment_status,
    COUNT(DISTINCT o.id) AS pedidos,
    SUM(o.total) AS valor_pedidos,
    SUM(p.amount) AS valor_pagamentos,
    SUM(o.total) - SUM(p.amount) AS diferenca
FROM staging.orders o
LEFT JOIN staging.payments p
    ON o.id = p.order_id
WHERE o.status IN ('paid', 'confirmed')
GROUP BY
    o.status,
    p.status
ORDER BY
    o.status,
    p.status;

-- =====================================================================
--Precisamos saber se todos os product_variant_id vendidos possuem cost_price válido.
-- =====================================================================

--itens sem custo
-- =====================================================================
SELECT
    COUNT(*) AS total_itens,
    COUNT(*) FILTER (
        WHERE pv.cost_price IS NULL
    ) AS itens_sem_custo,
    COUNT(*) FILTER (
        WHERE pv.cost_price IS NOT NULL
    ) AS itens_com_custo
FROM staging.order_items oi
LEFT JOIN staging.product_variants pv
    ON oi.product_variant_id = pv.id
WHERE EXISTS (
    SELECT 1
    FROM staging.orders o
    WHERE o.id = oi.order_id
      AND o.status IN ('paid', 'confirmed')
);

-- =====================================================================
--Variantes sem custo
-- =====================================================================
SELECT
    COUNT(DISTINCT oi.product_variant_id) AS variantes_vendidas,
    COUNT(DISTINCT oi.product_variant_id) FILTER (
        WHERE pv.cost_price IS NULL
    ) AS variantes_sem_custo
FROM staging.order_items oi
JOIN staging.orders o
    ON o.id = oi.order_id
LEFT JOIN staging.product_variants pv
    ON oi.product_variant_id = pv.id
WHERE o.status IN ('paid', 'confirmed');

-- =====================================================================
-- Cria ou atualiza a view analítica de vendas, reunindo informações
-- de pedidos, itens, produtos, categorias e marcas.
-- =====================================================================
CREATE OR REPLACE VIEW analytics.vendas3 AS
SELECT
    o.id AS order_id,
    o.order_number,
    o.placed_at::timestamp AS data_pedido,
    o.channel,
    o.customer_id,
    oi.id AS order_item_id,
    oi.product_variant_id,
    pv.product_id,
    p.name AS produto,
    c.name AS categoria,
    b.name AS marca,
    oi.quantity,
    oi.unit_price,
    oi.line_total AS valor_bruto_item,
    o.subtotal AS subtotal_pedido,
    o.discount_amount AS desconto_pedido,
    CASE
        WHEN o.subtotal > 0
        THEN oi.line_total / o.subtotal
        ELSE 0
    END AS percentual_item,
    CASE
        WHEN o.subtotal > 0
        THEN oi.line_total / o.subtotal * o.discount_amount
        ELSE 0
    END AS desconto_rateado,
    CASE
        WHEN o.subtotal > 0
        THEN oi.line_total
             - (oi.line_total / o.subtotal * o.discount_amount)
        ELSE oi.line_total
    END AS receita_liquida_item,
    pv.cost_price,
    oi.quantity * pv.cost_price AS custo_total,
    CASE
        WHEN o.subtotal > 0
        THEN (
            oi.line_total
            - (oi.line_total / o.subtotal * o.discount_amount)
        ) - (oi.quantity * pv.cost_price)
        ELSE oi.line_total - (oi.quantity * pv.cost_price)
    END AS lucro_item
FROM staging.orders o
JOIN staging.order_items oi
    ON o.id = oi.order_id
JOIN staging.product_variants pv
    ON oi.product_variant_id = pv.id
JOIN staging.products p
    ON pv.product_id = p.id
LEFT JOIN staging.categories c
    ON p.category_id = c.id
LEFT JOIN staging.brands b
    ON p.brand_id = b.id
WHERE o.status IN ('paid', 'confirmed');

-- =====================================================================
--quantidade de itens
-- =====================================================================
SELECT COUNT(*) AS quantidade_itens
FROM analytics.vendas3;

-- =====================================================================
--receita liquida
-- =====================================================================
SELECT
    SUM(receita_liquida_item) AS receita_liquida
FROM analytics.vendas3;

-- =====================================================================
--verificar se nossa distribuição de desconto preservou o total do pedido.
-- =====================================================================
SELECT
    SUM(receita_liquida_item) AS receita_itens,
    (
        SELECT SUM(total)
        FROM staging.orders
        WHERE status IN ('paid', 'confirmed')
    ) AS receita_pedidos,
    SUM(receita_liquida_item)
    -
    (
        SELECT SUM(total)
        FROM staging.orders
        WHERE status IN ('paid', 'confirmed')
    ) AS diferenca
FROM analytics.vendas3

-- =====================================================================
-- Identifica pedidos em que o valor total registrado diverge
-- da soma das receitas líquidas calculadas para seus itens.
-- Permite validar o rateio dos descontos e a consistência dos valores.
-- =====================================================================
SELECT
    o.id AS order_id,
    o.order_number,
    o.subtotal,
    o.discount_amount,
    o.total,
    SUM(v.valor_bruto_item) AS itens_bruto,
    SUM(v.desconto_rateado) AS desconto_rateado,
    SUM(v.receita_liquida_item) AS receita_itens,
    o.total - SUM(v.receita_liquida_item) AS diferenca
FROM staging.orders o
JOIN analytics.vendas3 v
    ON o.id = v.order_id
WHERE o.status IN ('paid', 'confirmed')
GROUP BY
    o.id,
    o.order_number,
    o.subtotal,
    o.discount_amount,
    o.total
HAVING ABS(
    o.total - SUM(v.receita_liquida_item)
) > 0.01
ORDER BY ABS(
    o.total - SUM(v.receita_liquida_item)
) DESC;

-- ====================================================================
-- Cria ou atualiza a view analítica de vendas, consolidando informações
-- de pedidos, itens, produtos, categorias e marcas para análise de receita,
-- custos e lucratividade.
-- ====================================================================
CREATE OR REPLACE VIEW analytics.vendas AS
SELECT
    -- Identificação do pedido
    o.id AS order_id,
    o.order_number,
    o.placed_at::timestamp AS data_pedido,
    o.channel,
    o.customer_id,
    -- Identificação do item
    oi.id AS order_item_id,
    oi.product_variant_id,
    -- Identificação do produto
    pv.product_id,
    p.name AS produto,
    c.name AS categoria,
    b.name AS marca,
    -- Quantidade e preço
    oi.quantity,
    oi.unit_price::NUMERIC(18,6) AS unit_price,
    -- Valor bruto do item
    oi.line_total::NUMERIC(18,6) AS valor_bruto_item,
    -- Informações do pedido
    o.subtotal::NUMERIC(18,6) AS subtotal_pedido,
    o.discount_amount::NUMERIC(18,6) AS desconto_pedido,
    o.total::NUMERIC(18,6) AS total_pedido,
    -- Participação do item no subtotal do pedido
    CASE
        WHEN o.subtotal::NUMERIC(18,6) > 0
        THEN
            oi.line_total::NUMERIC(18,6)
            / o.subtotal::NUMERIC(18,6)
        ELSE 0::NUMERIC
    END AS percentual_item,
    -- Desconto proporcionalmente rateado
    CASE
        WHEN o.subtotal::NUMERIC(18,6) > 0
        THEN
            (
                oi.line_total::NUMERIC(18,6)
                / o.subtotal::NUMERIC(18,6)
            )
            * o.discount_amount::NUMERIC(18,6)
        ELSE 0::NUMERIC
    END AS desconto_rateado,
    -- Receita líquida do item
    CASE
        WHEN o.subtotal::NUMERIC(18,6) > 0
        THEN
            oi.line_total::NUMERIC(18,6)
            -
            (
                (
                    oi.line_total::NUMERIC(18,6)
                    / o.subtotal::NUMERIC(18,6)
                )
                * o.discount_amount::NUMERIC(18,6)
            )
        ELSE
            oi.line_total::NUMERIC(18,6)
    END AS receita_liquida_item,
    -- Custo unitário
    pv.cost_price::NUMERIC(18,6) AS cost_price,
    -- Custo total do item
    (
        oi.quantity::NUMERIC(18,6)
        * pv.cost_price::NUMERIC(18,6)
    ) AS custo_total,
    -- Lucro do item
    CASE
        WHEN o.subtotal::NUMERIC(18,6) > 0
        THEN
            (
                oi.line_total::NUMERIC(18,6)
                -
                (
                    (
                        oi.line_total::NUMERIC(18,6)
                        / o.subtotal::NUMERIC(18,6)
                    )
                    * o.discount_amount::NUMERIC(18,6)
                )
            )
            -
            (
                oi.quantity::NUMERIC(18,6)
                * pv.cost_price::NUMERIC(18,6)
            )
        ELSE
            oi.line_total::NUMERIC(18,6)
            -
            (
                oi.quantity::NUMERIC(18,6)
                * pv.cost_price::NUMERIC(18,6)
            )
    END AS lucro_item
FROM staging.orders o
INNER JOIN staging.order_items oi
    ON o.id = oi.order_id
INNER JOIN staging.product_variants pv
    ON oi.product_variant_id = pv.id
INNER JOIN staging.products p
    ON pv.product_id = p.id
LEFT JOIN staging.categories c
    ON p.category_id = c.id
LEFT JOIN staging.brands b
    ON p.brand_id = b.id
WHERE o.status IN ('paid', 'confirmed');


-- =====================================================================
--Validação da View
-- =====================================================================
SELECT COUNT(*) AS quantidade_itens
FROM analytics.vendas;

-- =====================================================================
--Receita
-- =====================================================================
SELECT
    ROUND(SUM(receita_liquida_item), 2) AS receita_liquida,
    ROUND(SUM(custo_total), 2) AS custo,
    ROUND(SUM(lucro_item), 2) AS lucro,
    ROUND(
        SUM(lucro_item)
        / NULLIF(SUM(receita_liquida_item), 0) * 100,
        2
    ) AS margem_percentual
FROM analytics.vendas;

-- =====================================================================
--Reconciliação com orders
-- =====================================================================
SELECT
    ROUND(SUM(receita_liquida_item), 2) AS receita_itens,
    (
        SELECT ROUND(SUM(total::NUMERIC), 2)
        FROM staging.orders
        WHERE status IN ('paid', 'confirmed')
    ) AS receita_pedidos,
    ROUND(
        SUM(receita_liquida_item)
        -
        (
            SELECT SUM(total::NUMERIC)
            FROM staging.orders
            WHERE status IN ('paid', 'confirmed')
        ),
        2
    ) AS diferenca
FROM analytics.vendas;


-- =====================================================================
--ANÁLISE DE PRODUTOS COM PREJUÍZOS
-- =====================================================================

--Nossa primeira análise será no nível de produto, e não de SKU/variante.
--ordenados do maior prejuízo para o maior lucro.
-- =====================================================================
SELECT
    product_id,
    produto,
    categoria,
    ROUND(SUM(receita_liquida_item), 2) AS receita,
    ROUND(SUM(custo_total), 2) AS custo,
    ROUND(SUM(lucro_item), 2) AS lucro,
    ROUND(
        SUM(lucro_item)
        / NULLIF(SUM(receita_liquida_item), 0) * 100,
        2
    ) AS margem_percentual,
    SUM(quantity) AS quantidade_vendida
FROM analytics.vendas
GROUP BY
    product_id,
    produto,
    categoria
ORDER BY lucro ASC;

-- =====================================================================
--Quantidade de Produtivos lucrativos (lucro maior que 0)
-- =====================================================================
SELECT
    COUNT(*) AS total_produtos,
    COUNT(*) FILTER (WHERE lucro < 0) AS produtos_prejuizo,
    COUNT(*) FILTER (WHERE lucro = 0) AS produtos_empate,
    COUNT(*) FILTER (WHERE lucro > 0) AS produtos_lucrativos
FROM (
    SELECT
        product_id,
        produto,
        SUM(lucro_item) AS lucro
    FROM analytics.vendas
    GROUP BY
        product_id,
        produto
) AS produtos;

-- =====================================================================
--PRODUTOS COM MENOR LUCRO
-- =====================================================================
SELECT
    product_id,
    produto,
    categoria,
    ROUND(SUM(receita_liquida_item), 2) AS receita,
    ROUND(SUM(custo_total), 2) AS custo,
    ROUND(SUM(lucro_item), 2) AS lucro,
    ROUND(
        SUM(lucro_item)
        / NULLIF(SUM(receita_liquida_item), 0) * 100,
        2
    ) AS margem_percentual,
    SUM(quantity) AS quantidade_vendida
FROM analytics.vendas
GROUP BY
    product_id,
    produto,
    categoria
ORDER BY lucro ASC
LIMIT 20;

-- =====================================================================
--PRODUTOS COM MENOR MARGEM DE LUCRO
-- =====================================================================
SELECT
    product_id,
    produto,
    categoria,
    ROUND(SUM(receita_liquida_item), 2) AS receita,
    ROUND(SUM(custo_total), 2) AS custo,
    ROUND(SUM(lucro_item), 2) AS lucro,
    ROUND(
        SUM(lucro_item)
        / NULLIF(SUM(receita_liquida_item), 0) * 100,
        2
    ) AS margem_percentual,
    SUM(quantity) AS quantidade_vendida
FROM analytics.vendas
GROUP BY
    product_id,
    produto,
    categoria
HAVING SUM(receita_liquida_item) > 0
ORDER BY margem_percentual ASC
LIMIT 20;


-- =====================================================================
--PRODUTOS QUE MAIS CONTRIBUEM PARA O LUCRO DA EMPRESA
-- =====================================================================
SELECT
    product_id,
    produto,
    categoria,
    ROUND(SUM(receita_liquida_item), 2) AS receita,
    ROUND(SUM(custo_total), 2) AS custo,
    ROUND(SUM(lucro_item), 2) AS lucro,
    ROUND(
        SUM(lucro_item)
        / NULLIF(SUM(receita_liquida_item), 0) * 100,
        2
    ) AS margem_percentual,
    SUM(quantity) AS quantidade_vendida,
    ROUND(
        SUM(lucro_item)
        / NULLIF(
            SUM(SUM(lucro_item)) OVER (),
            0
        ) * 100,
        2
    ) AS participacao_lucro_percentual
FROM analytics.vendas
GROUP BY
    product_id,
    produto,
    categoria
ORDER BY lucro DESC
LIMIT 20;

-- =====================================================================
--Vamos calcular quanto do lucro total está concentrado nos Top 10 produtos:
-- =====================================================================
WITH produtos AS (
    SELECT
        product_id,
        produto,
        SUM(lucro_item) AS lucro
    FROM analytics.vendas
    GROUP BY
        product_id,
        produto
),
ranking AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY lucro DESC
        ) AS ranking
    FROM produtos
)
SELECT
    SUM(lucro) FILTER (WHERE ranking <= 10) AS lucro_top_10,
    SUM(lucro) AS lucro_total,
    ROUND(
        SUM(lucro) FILTER (WHERE ranking <= 10)
        / NULLIF(SUM(lucro), 0) * 100,
        2
    ) AS participacao_top_10_percentual
FROM ranking;

--TOP 20
WITH produtos AS (
    SELECT
        product_id,
        produto,
        SUM(lucro_item) AS lucro
    FROM analytics.vendas
    GROUP BY
        product_id,
        produto
),
ranking AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY lucro DESC
        ) AS ranking
    FROM produtos
)
SELECT
    SUM(lucro) FILTER (WHERE ranking <= 20) AS lucro_top_20,
    SUM(lucro) AS lucro_total,
    ROUND(
        SUM(lucro) FILTER (WHERE ranking <= 20)
        / NULLIF(SUM(lucro), 0) * 100,
        2
    ) AS participacao_top_20_percentual
FROM ranking;

-- =====================================================================
--DESCOBRIR VENDAS POR PERÍODO
-- =====================================================================
--Vendas médias por dia da semana considerando dias sem venda.
-- =====================================================================

--descobrir exatamente o intervalo das vendas consideradas.
-- =====================================================================
SELECT
    MIN(placed_at) AS primeira_venda,
    MAX(placed_at) AS ultima_venda
FROM staging.orders
WHERE status IN ('paid', 'confirmed');


-- =====================================================================
-- Gera um calendário diário de 2020 a 2026 para analisar o comportamento
-- das vendas por dia da semana, incluindo dias sem vendas.
-- =====================================================================
WITH calendario AS (
    SELECT
        generate_series(
            DATE '2020-01-01',
            DATE '2026-12-31',
            INTERVAL '1 day'
        )::date AS data
),
vendas_diarias AS (
    SELECT
        placed_at::date AS data,
        SUM(total) AS vendas
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
    GROUP BY placed_at::date
),
dias AS (
    SELECT
        c.data,
        COALESCE(v.vendas, 0) AS vendas,
        EXTRACT(DOW FROM c.data)::integer AS numero_dia
    FROM calendario c
    LEFT JOIN vendas_diarias v
        ON c.data = v.data
)
SELECT
    numero_dia,
    CASE numero_dia
        WHEN 0 THEN 'Domingo'
        WHEN 1 THEN 'Segunda-feira'
        WHEN 2 THEN 'Terça-feira'
        WHEN 3 THEN 'Quarta-feira'
        WHEN 4 THEN 'Quinta-feira'
        WHEN 5 THEN 'Sexta-feira'
        WHEN 6 THEN 'Sábado'
    END AS dia_semana,
    COUNT(*) AS quantidade_dias,
    COUNT(*) FILTER (
        WHERE vendas > 0
    ) AS dias_com_venda,
    COUNT(*) FILTER (
        WHERE vendas = 0
    ) AS dias_sem_venda,
    SUM(vendas) AS vendas_totais,
    ROUND(AVG(vendas), 2) AS vendas_medias_por_dia
FROM dias
GROUP BY numero_dia
ORDER BY numero_dia;

-- =====================================================================
--EVOLUÇÃO MENSAL E SAZONALIDADE
-- =====================================================================

--Faturamento por mês
-- =====================================================================
SELECT
    DATE_TRUNC('month', placed_at)::date AS mes,
    COUNT(*) AS quantidade_pedidos,
    SUM(total) AS faturamento,
    AVG(total) AS ticket_medio
FROM staging.orders
WHERE status IN ('paid', 'confirmed')
GROUP BY DATE_TRUNC('month', placed_at)
ORDER BY mes;

-- =====================================================================
--Faturamento anual
-- =====================================================================
SELECT
    EXTRACT(YEAR FROM placed_at)::integer AS ano,
    COUNT(*) AS quantidade_pedidos,
    SUM(total) AS faturamento,
    AVG(total) AS ticket_medio
FROM staging.orders
WHERE status IN ('paid', 'confirmed')
GROUP BY EXTRACT(YEAR FROM placed_at)
ORDER BY ano;

-- =====================================================================
--Crescimento YoY
-- =====================================================================
WITH vendas_anuais AS (
    SELECT
        EXTRACT(YEAR FROM placed_at)::integer AS ano,
        COUNT(*) AS pedidos,
        SUM(total) AS faturamento,
        AVG(total) AS ticket_medio
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
    GROUP BY EXTRACT(YEAR FROM placed_at)
),
comparacao AS (
    SELECT
        ano,
        pedidos,
        faturamento,
        ticket_medio,
        LAG(faturamento) OVER (
            ORDER BY ano
        ) AS faturamento_ano_anterior
    FROM vendas_anuais
)
SELECT
    ano,
    pedidos,
    faturamento,
    ticket_medio,
    faturamento_ano_anterior,
    ROUND(
        (
            (faturamento - faturamento_ano_anterior)
            / NULLIF(faturamento_ano_anterior, 0)
        ) * 100,
        2
    ) AS crescimento_yoy_pct
FROM comparacao
ORDER BY ano;

-- =====================================================================
--SAZONALIDADE POR MÊS DO ANO
-- =====================================================================

--Existe algum mês do ano que historicamente apresenta desempenho superior ou inferior?
-- =====================================================================
WITH vendas_mensais AS (
    SELECT
        DATE_TRUNC('month', placed_at)::date AS mes,
        EXTRACT(MONTH FROM placed_at)::integer AS numero_mes,
        SUM(total) AS faturamento,
        COUNT(*) AS pedidos,
        AVG(total) AS ticket_medio
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
    GROUP BY
        DATE_TRUNC('month', placed_at)::date,
        EXTRACT(MONTH FROM placed_at)::integer
)
SELECT
    numero_mes,
    CASE numero_mes
        WHEN 1 THEN 'Janeiro'
        WHEN 2 THEN 'Fevereiro'
        WHEN 3 THEN 'Março'
        WHEN 4 THEN 'Abril'
        WHEN 5 THEN 'Maio'
        WHEN 6 THEN 'Junho'
        WHEN 7 THEN 'Julho'
        WHEN 8 THEN 'Agosto'
        WHEN 9 THEN 'Setembro'
        WHEN 10 THEN 'Outubro'
        WHEN 11 THEN 'Novembro'
        WHEN 12 THEN 'Dezembro'
    END AS mes,
    COUNT(*) AS quantidade_anos,
    SUM(pedidos) AS pedidos_totais,
    SUM(faturamento) AS faturamento_total,
    ROUND(AVG(faturamento), 2) AS faturamento_medio_historico,
    ROUND(AVG(ticket_medio), 2) AS ticket_medio_historico
FROM vendas_mensais
GROUP BY numero_mes
ORDER BY numero_mes;

-- =====================================================================
--Por ano
-- =====================================================================
SELECT
    EXTRACT(YEAR FROM placed_at)::integer AS ano,
    COUNT(*) AS quantidade_pedidos,
    SUM(total) AS faturamento,
    AVG(total) AS ticket_medio
FROM staging.orders
WHERE status IN ('paid', 'confirmed')
GROUP BY EXTRACT(YEAR FROM placed_at)
ORDER BY ano;

-- =====================================================================
--Sazonalidade por Mês
-- =====================================================================
--Esse crescimento é distribuído de forma uniforme ao longo do ano ou existem meses estruturalmente mais fortes/fracos?
-- =====================================================================
WITH vendas_mensais AS (
    SELECT
        DATE_TRUNC('month', placed_at)::date AS mes,
        EXTRACT(MONTH FROM placed_at)::integer AS numero_mes,
        SUM(total) AS faturamento,
        COUNT(*) AS pedidos,
        AVG(total) AS ticket_medio
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
    GROUP BY
        DATE_TRUNC('month', placed_at)::date,
        EXTRACT(MONTH FROM placed_at)::integer
)
SELECT
    numero_mes,
    CASE numero_mes
        WHEN 1 THEN 'Janeiro'
        WHEN 2 THEN 'Fevereiro'
        WHEN 3 THEN 'Março'
        WHEN 4 THEN 'Abril'
        WHEN 5 THEN 'Maio'
        WHEN 6 THEN 'Junho'
        WHEN 7 THEN 'Julho'
        WHEN 8 THEN 'Agosto'
        WHEN 9 THEN 'Setembro'
        WHEN 10 THEN 'Outubro'
        WHEN 11 THEN 'Novembro'
        WHEN 12 THEN 'Dezembro'
    END AS mes,
    COUNT(*) AS quantidade_anos,
    SUM(pedidos) AS pedidos_totais,
    SUM(faturamento) AS faturamento_total,
    ROUND(AVG(faturamento), 2) AS faturamento_medio_historico,
    ROUND(AVG(ticket_medio), 2) AS ticket_medio_historico
FROM vendas_mensais
GROUP BY numero_mes
ORDER BY numero_mes;

-- =====================================================================
--ANÁLISE POR CLIENTES
-- =====================================================================

--Faturamento por cliente (ordenado do maior)
-- =====================================================================
SELECT
    customer_id,
    COUNT(*) AS quantidade_pedidos,
    SUM(total) AS faturamento,
    AVG(total) AS ticket_medio
FROM staging.orders
WHERE status IN ('paid', 'confirmed')
GROUP BY customer_id
ORDER BY faturamento desc;


-- =====================================================================
--Compreendendo a distribuição do faturamento
-- =====================================================================

--Qual percentual da receita total está concentrado nos Top 10, Top 20, Top 50 e Top 100 clientes?
-- =====================================================================
WITH clientes AS (
    SELECT
        customer_id,
        SUM(total) AS faturamento
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
      AND customer_id IS NOT NULL
    GROUP BY customer_id
),
ranking AS (
    SELECT
        customer_id,
        faturamento,
        ROW_NUMBER() OVER (
            ORDER BY faturamento DESC
        ) AS ranking
    FROM clientes
),
total AS (
    SELECT
        SUM(faturamento) AS faturamento_total
    FROM clientes
)
SELECT
    'Top 10' AS grupo,
    COUNT(*) AS quantidade_clientes,
    SUM(r.faturamento) AS faturamento,
    ROUND(
        SUM(r.faturamento) / MAX(t.faturamento_total) * 100,
        2
    ) AS participacao_pct
FROM ranking r
CROSS JOIN total t
WHERE r.ranking <= 10
UNION ALL
SELECT
    'Top 20',
    COUNT(*),
    SUM(r.faturamento),
    ROUND(
        SUM(r.faturamento) / MAX(t.faturamento_total) * 100,
        2
    )
FROM ranking r
CROSS JOIN total t
WHERE r.ranking <= 20
UNION ALL
SELECT
    'Top 50',
    COUNT(*),
    SUM(r.faturamento),
    ROUND(
        SUM(r.faturamento) / MAX(t.faturamento_total) * 100,
        2
    )
FROM ranking r
CROSS JOIN total t
WHERE r.ranking <= 50
UNION ALL
SELECT
    'Top 100',
    COUNT(*),
    SUM(r.faturamento),
    ROUND(
        SUM(r.faturamento) / MAX(t.faturamento_total) * 100,
        2
    )
FROM ranking r
CROSS JOIN total t
WHERE r.ranking <= 100
ORDER BY
    quantidade_clientes;

-- =====================================================================
--CALCULAR RFM
-- =====================================================================
--Recência, Frequência e Valor
-- =====================================================================
WITH vendas AS (
    SELECT
        customer_id,
        created_at,
        total
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
      AND customer_id IS NOT NULL
),
rfm AS (
    SELECT
        customer_id,
        -- Recência em dias
        '2026-12-31'::date - MAX(created_at)::date AS recencia,
        -- Frequência
        COUNT(*) AS frequencia,
        -- Valor monetário
        SUM(total) AS valor_monetario
    FROM vendas
    GROUP BY customer_id
)
SELECT *
FROM rfm
ORDER BY valor_monetario DESC;

-- =====================================================================
--Criar os scores RFM
-- =====================================================================
WITH vendas AS (
    SELECT
        customer_id,
        created_at,
        total
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
      AND customer_id IS NOT NULL
),
rfm AS (
    SELECT
        customer_id,
        '2026-12-31'::date - MAX(created_at)::date AS recencia,
        COUNT(*) AS frequencia,
        SUM(total) AS valor_monetario
    FROM vendas
    GROUP BY customer_id
),
scores AS (
    SELECT
        customer_id,
        recencia,
        frequencia,
        valor_monetario,
        -- Recência: menor é melhor
        6 - NTILE(5) OVER (
            ORDER BY recencia ASC
        ) AS r_score,
        -- Frequência: maior é melhor
        NTILE(5) OVER (
            ORDER BY frequencia ASC
        ) AS f_score,
        -- Valor: maior é melhor
        NTILE(5) OVER (
            ORDER BY valor_monetario ASC
        ) AS m_score
    FROM rfm
)
SELECT
    *,
    CONCAT(r_score, f_score, m_score) AS rfm_score
FROM scores
ORDER BY valor_monetario DESC;

-- =====================================================================
--Resultado agregado para os scores de RFM
-- =====================================================================
WITH vendas AS (
    SELECT
        customer_id,
        created_at,
        total
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
      AND customer_id IS NOT NULL
),
rfm AS (
    SELECT
        customer_id,
        '2026-12-31'::date - MAX(created_at)::date AS recencia,
        COUNT(*) AS frequencia,
        SUM(total) AS valor_monetario
    FROM vendas
    GROUP BY customer_id
),
scores AS (
    SELECT
        *,
        6 - NTILE(5) OVER (ORDER BY recencia ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequencia ASC) AS f_score,
        NTILE(5) OVER (ORDER BY valor_monetario ASC) AS m_score
    FROM rfm
)
SELECT
    r_score,
    f_score,
    m_score,
    COUNT(*) AS clientes,
    SUM(valor_monetario) AS faturamento
FROM scores
GROUP BY
    r_score,
    f_score,
    m_score
ORDER BY
    r_score DESC,
    f_score DESC,
    m_score DESC;

-- =====================================================================
--consulta que calcula segmento, quantidade de clientes e faturamento.
-- =====================================================================
WITH vendas AS (
    SELECT
        customer_id,
        created_at,
        total
    FROM staging.orders
    WHERE status IN ('paid', 'confirmed')
      AND customer_id IS NOT NULL
),
rfm AS (
    SELECT
        customer_id,
        '2026-12-31'::date - MAX(created_at)::date AS recencia,
        COUNT(*) AS frequencia,
        SUM(total) AS valor_monetario
    FROM vendas
    GROUP BY customer_id
),
scores AS (
    SELECT
        *,
        6 - NTILE(5) OVER (
            ORDER BY recencia ASC
        ) AS r_score,
        NTILE(5) OVER (
            ORDER BY frequencia ASC
        ) AS f_score,
        NTILE(5) OVER (
            ORDER BY valor_monetario ASC
        ) AS m_score
    FROM rfm
),
segmentacao AS (
    SELECT
        *,
        CASE
            WHEN r_score >= 4
             AND f_score >= 4
             AND m_score >= 4
                THEN 'Campeões / VIP'
            WHEN r_score >= 4
             AND f_score >= 4
             AND m_score < 4
                THEN 'Clientes fiéis'
            WHEN r_score <= 2
             AND f_score >= 4
             AND m_score >= 4
                THEN 'Alto valor em risco'
            WHEN r_score <= 2
             AND f_score >= 3
                THEN 'Clientes em risco'
            WHEN r_score >= 4
             AND f_score <= 2
                THEN 'Clientes recentes'
            WHEN r_score <= 2
             AND f_score <= 2
             AND m_score <= 2
                THEN 'Inativos / baixo valor'
            ELSE 'Clientes intermediários'
        END AS segmento
    FROM scores
)
SELECT
    segmento,
    COUNT(*) AS clientes,
    SUM(valor_monetario) AS faturamento,
    ROUND(
        100.0 * SUM(valor_monetario)
        / SUM(SUM(valor_monetario)) OVER (),
        2
    ) AS percentual_faturamento,
    ROUND(
        AVG(valor_monetario),
        2
    ) AS ticket_medio_cliente
FROM segmentacao
GROUP BY segmento
ORDER BY faturamento DESC;


-- =====================================================================
--VALIDAÇÃO DOS DADOS (SOBRE FATURAMENTO)
-- =====================================================================

--vERIFICANDO SE OS DESCONTOS SÃO POR PEDIDO OU ITEM
-- =====================================================================
SELECT
    order_id,
    COUNT(*) AS qtd_itens,
    COUNT(DISTINCT discount_amount) AS qtd_descontos_diferentes,
    MIN(discount_amount) AS menor_desconto,
    MAX(discount_amount) AS maior_desconto
FROM analytics.fact_vendas
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY qtd_itens DESC;


-- =====================================================================
-- Identifica pedidos em que o subtotal registrado no pedido
-- difere da soma dos valores dos itens em mais de 0,01.
-- Permite detectar possíveis inconsistências nos valores dos pedidos.
SELECT
    o.id AS order_id,
    o.subtotal,
    SUM(oi.line_total) AS subtotal_itens,
    o.discount_amount,
    o.total
FROM staging.orders o
INNER JOIN staging.order_items oi
    ON oi.order_id = o.id
GROUP BY
    o.id,
    o.subtotal,
    o.discount_amount,
    o.total
HAVING ABS(o.subtotal - SUM(oi.line_total)) > 0.01;