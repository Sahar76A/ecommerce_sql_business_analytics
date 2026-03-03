-- This view gives a snapshot about every order id and is a quick way to extract details about a particular order --
CREATE OR REPLACE VIEW vw_order_line AS
SELECT
	o.order_id,
	o.customer_id,
	c.customer_unique_id,
	c.customer_city,
	c.customer_state,
	o.order_status,
	o.order_purchase_timestamp,
	o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value,
    op.payment_sequential,
    op.payment_type,
    op.payment_installments,
    op.payment_value	
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
LEFT JOIN order_payments op ON op.order_id = o.order_id
	

-- This view gives a snapshot regarding order delivery and can be used to track order delivery times --
CREATE OR REPLACE VIEW vw_order_delivery AS
SELECT 
	o.order_id,
	o.customer_id,
	o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

	CASE
		WHEN o.order_approved_at IS NOT NULL
		THEN EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400.0
	END AS days_purchase_to_approval,

	CASE
		WHEN o.order_delivered_carrier_date IS NOT NULL
			AND o.order_approved_at IS NOT NULL
		THEN EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at))/ 86400.0
	END AS days_approval_to_carrier,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_delivered_carrier_date IS NOT NULL
        THEN EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400.0
    END AS days_carrier_to_customer,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0
    END AS days_purchase_to_delivery,

    -- Late flag: delivered after estimated date
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date THEN 1
        ELSE 0
    END AS is_late

FROM orders o;


CREATE OR REPLACE VIEW vw_order_summary AS
WITH items AS(
	SELECT
		order_id,
		COUNT(*) as items_count,
		SUM(price) as items_value,
		SUM(freight_value) as freight_value,
		SUM(price + freight_value) as order_gmv
	FROM vw_order_line
	GROUP BY order_id
),
payments AS(
	SELECT
		order_id,
		SUM(payment_value) as payment_total,
		COUNT(*) as payment_rows,
		MAX(payment_installments) as max_installments
	FROM order_payments
	GROUP BY order_id
),
reviews AS(
	SELECT
		order_id,
		AVG(review_score)::numeric(10,2) as avg_review_score,
		COUNT(*) as review_count
	FROM order_reviews
	GROUP BY order_id
)

SELECT 
	o.order_id,
	o.customer_id,
	o.order_status,
	o.order_purchase_timestamp,
	o.order_approved_at,
	o.order_delivered_carrier_date,
	o.order_delivered_customer_date,
	o.order_estimated_delivery_date,
	i.items_count,
	i.items_value,
	i.freight_value,
	i.order_gmv,
	p.payment_total,
	p.payment_rows,
	p.max_installments,
	r.avg_review_score,
	r.review_count,
	(o.order_delivered_customer_date - o.order_purchase_timestamp) AS days_puchase_to_delivery,
	(o.order_estimated_delivery_date - o.order_delivered_customer_date) AS days_early_or_late
FROM orders o
LEFT JOIN items i on i.order_id = o.order_id
LEFT JOIN payments p on p.order_id = o.order_id
LEFT JOIN reviews r on r.order_id = o.order_id;


CREATE OR REPLACE VIEW vw_order_item_summary AS
SELECT
  oi.order_id,

  COUNT(*) AS line_count,                              -- total rows in order_items for this order
  SUM(oi.order_item_id) AS item_id_sum,                
  COUNT(DISTINCT oi.product_id) AS distinct_products,  -- how many unique products in the order
  COUNT(DISTINCT oi.seller_id)  AS distinct_sellers,   -- how many sellers fulfilled this order

  MIN(oi.shipping_limit_date) AS first_shipping_limit_date,
  MAX(oi.shipping_limit_date) AS last_shipping_limit_date,

  SUM(oi.price)         AS items_value,                -- total product value (no freight)
  SUM(oi.freight_value) AS freight_value,              -- total shipping cost
  SUM(oi.price + oi.freight_value) AS order_gmv         -- gross merchandise value (items + freight)
FROM order_items oi
GROUP BY oi.order_id;


CREATE OR REPLACE VIEW analytics.vw_dim_date AS
WITH all_dates AS (
    -- Order purchase dates
    SELECT order_purchase_timestamp::date AS dt
    FROM orders
    WHERE order_purchase_timestamp IS NOT NULL

    UNION

    -- Actual delivery dates
    SELECT order_delivered_customer_date::date AS dt
    FROM orders
    WHERE order_delivered_customer_date IS NOT NULL

    UNION

    -- Estimated delivery dates
    SELECT order_estimated_delivery_date::date AS dt
    FROM orders
    WHERE order_estimated_delivery_date IS NOT NULL
)
SELECT
    dt                                   AS date_key,      -- primary date key
    EXTRACT(YEAR FROM dt)::int           AS year,
    EXTRACT(QUARTER FROM dt)::int        AS quarter,
    EXTRACT(MONTH FROM dt)::int          AS month,
    TO_CHAR(dt, 'Mon')                   AS month_name,
    DATE_TRUNC('month', dt)::date        AS month_start,
    EXTRACT(ISODOW FROM dt)::int         AS iso_day_of_week,
    TO_CHAR(dt, 'Dy')                    AS day_name,
    CASE 
        WHEN EXTRACT(ISODOW FROM dt) IN (6, 7) THEN TRUE 
        ELSE FALSE 
    END                                  AS is_weekend
FROM all_dates;


CREATE OR REPLACE VIEW analytics.vw_dim_customer AS
WITH customer_orders AS (
    SELECT
        ol.customer_id,
        ol.customer_unique_id,
        ol.customer_city,
        ol.customer_state,
        COUNT(DISTINCT ol.order_id) AS total_orders,
        MIN(ol.order_purchase_timestamp) AS first_order_ts,
        MAX(ol.order_purchase_timestamp) AS last_order_ts,
        SUM(ol.price + ol.freight_value) AS lifetime_gmv,
        AVG(ol.price + ol.freight_value) AS avg_item_gmv
    FROM analytics.vw_order_line ol
    GROUP BY
        ol.customer_id,
        ol.customer_unique_id,
        ol.customer_city,
        ol.customer_state
),
customer_review AS (
    SELECT
        ol.customer_id,
        AVG(orv.review_score::numeric) AS avg_review_score
    FROM analytics.vw_order_line ol
    JOIN public.order_reviews orv
        ON orv.order_id = ol.order_id
    GROUP BY ol.customer_id
)
SELECT
    co.customer_id,
    co.customer_unique_id,
    co.customer_city,
    co.customer_state,
    co.total_orders,
    co.first_order_ts,
    co.last_order_ts,
    co.lifetime_gmv,
    co.avg_item_gmv,
    cr.avg_review_score
FROM customer_orders co
LEFT JOIN customer_review cr
    ON cr.customer_id = co.customer_id;


CREATE OR REPLACE VIEW analytics.vw_dim_seller AS
SELECT
    s.seller_id,
    s.seller_zip_code_prefix,
    INITCAP(TRIM(s.seller_city)) AS seller_city,
    UPPER(TRIM(s.seller_state))  AS seller_state
FROM public.sellers s;


CREATE OR REPLACE VIEW analytics.vw_dim_product AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name) AS product_category,
    p.product_category_name,
    p.product_name_length,
    p.product_description_length,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM public.products p
LEFT JOIN public.product_category_name_translation t
    ON t.product_category_name = p.product_category_name;


-- Daily Fact Table --
CREATE OR REPLACE VIEW analytics.vw_fact_sales_daily AS
SELECT
	DATE(ol.order_purchase_timestamp) AS order_date,
	COUNT(DISTINCT(ol.order_id)) AS num_orders,
	SUM(ol.price + ol.freight_value) AS day_revenue,
    ROUND(
        SUM(ol.price + ol.freight_value) / NULLIF(COUNT(DISTINCT ol.order_id), 0)
    , 2)                              AS avg_order_value
FROM analytics.vw_order_line ol
WHERE ol.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1;


CREATE OR REPLACE VIEW analytics.vw_fact_order AS
WITH payments AS (
    SELECT
        op.order_id,
        SUM(op.payment_value) AS payment_total,
        COUNT(*)              AS payment_count,
        MIN(op.payment_sequential) AS first_payment_seq,
        MAX(op.payment_sequential) AS last_payment_seq
    FROM public.order_payments op
    GROUP BY op.order_id
),
items AS (
    SELECT
        oi.order_id,
        COUNT(*) AS item_rows,
        COUNT(DISTINCT oi.product_id) AS distinct_products,
        COUNT(DISTINCT oi.seller_id)  AS distinct_sellers,
        SUM(oi.price)         AS items_subtotal,
        SUM(oi.freight_value) AS freight_total
    FROM public.order_items oi
    GROUP BY oi.order_id
),
reviews AS (
    SELECT
        r.order_id,
        AVG(r.review_score)::numeric(10,2) AS avg_review_score,
        COUNT(*) AS review_count
    FROM public.order_reviews r
    GROUP BY r.order_id
)
SELECT
    o.order_id,
    o.customer_id,

    -- Date keys to join to dim_date
    o.order_purchase_timestamp::date            AS purchase_date,
    o.order_approved_at::date                   AS approved_date,
    o.order_delivered_carrier_date::date        AS carrier_date,
    o.order_delivered_customer_date::date       AS delivered_date,
    o.order_estimated_delivery_date::date       AS estimated_delivery_date,

    o.order_status,

    -- Measures
    COALESCE(i.item_rows, 0)            AS item_rows,
    COALESCE(i.distinct_products, 0)    AS distinct_products,
    COALESCE(i.distinct_sellers, 0)     AS distinct_sellers,

    COALESCE(i.items_subtotal, 0)       AS items_subtotal,
    COALESCE(i.freight_total, 0)        AS freight_total,
    COALESCE(p.payment_total, 0)        AS payment_total,

    COALESCE(r.avg_review_score, NULL)  AS avg_review_score,
    COALESCE(r.review_count, 0)         AS review_count,

    -- Useful delivery KPIs (in days)
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_purchase_timestamp IS NOT NULL
        THEN (o.order_delivered_customer_date::date - o.order_purchase_timestamp::date)
        ELSE NULL
    END AS days_to_deliver,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date)
        ELSE NULL
    END AS delivery_vs_estimated_days

FROM public.orders o
LEFT JOIN items   i ON i.order_id = o.order_id
LEFT JOIN payments p ON p.order_id = o.order_id
LEFT JOIN reviews r ON r.order_id = o.order_id;
