-- Portfolio SQL Queries
-- Dataset: Olist E-commerce
-- Author: Kartikay Sachdeva

-- Query 1: Executive-Level Snapshot, provides key information to stakeholders --
SELECT
  COUNT(*) AS total_orders,
  ROUND(SUM(order_gmv)::numeric, 2) AS total_gmv,
  ROUND(AVG(order_gmv)::numeric, 2) AS avg_order_value,
  ROUND(AVG(avg_review_score)::numeric, 2) AS avg_review_score,
  ROUND(AVG(EXTRACT(EPOCH FROM days_purchase_to_delivery) /86400)::numeric, 2) AS avg_days_purchase_to_delivery,
  ROUND(
    100.0 * AVG(CASE WHEN days_early_or_late <= INTERVAL '0 days' THEN 1 ELSE 0 END)
  , 2) AS on_time_delivery_pct
FROM analytics.vw_order_summary
WHERE order_status = 'delivered';
--Business Use: This query creates a single “at-a-glance” view of business performance for leadership.--
--It answers: How big is the business right now, how many orders/customers are we serving, and what does an average order look like?--


--Query 2: Monthly KPI's, for executive level tracking--
SELECT
  DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
  COUNT(*) AS orders,
  ROUND(SUM(order_gmv)::numeric, 2) AS gmv,
  ROUND(AVG(order_gmv)::numeric, 2) AS aov,
  ROUND(AVG(avg_review_score)::numeric, 2) AS avg_review,
  ROUND(AVG(EXTRACT(EPOCH FROM days_purchase_to_delivery)::numeric / 86400), 2) AS avg_days_to_deliver,
  ROUND(
    100.0 * AVG(CASE WHEN days_early_or_late <= INTERVAL '0 days' THEN 1 ELSE 0 END)
  , 2) AS on_time_pct
FROM analytics.vw_order_summary
WHERE order_status = 'delivered'
GROUP BY 1
ORDER BY 1;
--Business Use: This query tracks business performance month-by-month, helping stakeholders spot seasonality, growth/decline trends, and unusual spikes.


--Query 3: Top product categories by revenue + cumulative % of total--
WITH category_rev AS (
    SELECT
        COALESCE(pcnt.product_category_name_english, p.product_category_name) AS category,
        SUM(ol.price + ol.freight_value) AS revenue
    FROM analytics.vw_order_line ol
    JOIN public.products p
        ON p.product_id = ol.product_id
    LEFT JOIN public.product_category_name_translation pcnt
        ON pcnt.product_category_name = p.product_category_name
    WHERE ol.order_status = 'delivered'
    GROUP BY 1
),
ranked AS (
    SELECT
        category,
        revenue,
        SUM(revenue) OVER () AS total_revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC) AS cumulative_revenue
    FROM category_rev
)
SELECT
    category,
    ROUND(revenue::numeric, 2) AS revenue,
    ROUND((revenue / total_revenue) * 100, 2) AS pct_of_total,
    ROUND((cumulative_revenue / total_revenue) * 100, 2) AS cumulative_pct
FROM ranked
ORDER BY revenue DESC
LIMIT 15;
--Business Use: This query identifies which product categories drive the most revenue and applies a Pareto-style (80/20) analysis using cumulative percent of total revenue.--


--Query 4: Seller Performance, based on revenue generated, orders and avg freight share--

WITH seller_perf AS(
	SELECT
		seller_id,
		COUNT(DISTINCT order_id) AS orders,
		SUM(price + freight_value) AS revenue,
		AVG(freight_value / NULLIF(price + freight_value, 0)) AS avg_freight_share
	FROM analytics.vw_order_line
	WHERE order_status IN ('delivered', 'shipped', 'invoiced')
	GROUP BY seller_id
)
SELECT
	seller_id,
	orders,
	ROUND(revenue::numeric, 2) AS revenue,
	ROUND((avg_freight_share * 100)::numeric,2) AS avg_freight_pct
FROM seller_perf
ORDER BY revenue DESC
LIMIT 50;
--Business Use: This query evaluates seller contribution and efficiency.-- 
--It answers: Which sellers generate the most revenue, handle the most orders, and how much freight cost burden is associated with their sales?--
	

--Query 5: Customer Segmentation, RFM--
WITH customer_rfm AS(
	SELECT
		ol.customer_unique_id,
		COUNT(DISTINCT order_id) AS order_count,
		SUM(ol.price + ol.freight_value) AS total_revenue,
		MAX(ol.order_purchase_timestamp)::date AS last_purchase_date,
		(CURRENT_DATE - MAX(ol.order_purchase_timestamp)::date) AS recency_days
	FROM analytics.vw_order_line ol
	WHERE ol.order_status IN ('delivered', 'shipped', 'invoiced')
	GROUP BY ol.customer_unique_id
)
SELECT
	customer_unique_id,
	order_count,
	ROUND(total_revenue::numeric,2) as total_revenue,
	last_purchase_date,
	recency_days,
	CASE
		WHEN order_count >= 5 AND total_revenue >= 500 AND recency_days <= 60
			THEN 'Champions'
		WHEN order_count >= 3 AND recency_days <= 90
			THEN 'Loyal'
		WHEN order_count = 1 AND recency_days <= 60
			THEN 'New'
		WHEN recency_days > 180
			THEN 'At-Risk'
		ELSE 'Regular'
	END AS segment
FROM customer_rfm
ORDER BY total_revenue DESC
LIMIT 50;
--Business Use: This query segments customers using the widely-used RFM framework.
--It answers: Who are our best customers, who is at risk, and who is new?--


-- Query 6: On-time delivery performance by month and state --
WITH delivered AS (
  SELECT
    TO_CHAR(od.order_purchase_timestamp, 'MONTH') AS month_name,
	c.customer_state,
    od.order_id,
    od.order_purchase_timestamp,
    od.order_delivered_customer_date,
    od.order_estimated_delivery_date,
    CASE
      WHEN od.order_delivered_customer_date <= od.order_estimated_delivery_date THEN 1
      ELSE 0
    END AS is_on_time,
    EXTRACT(EPOCH FROM (od.order_delivered_customer_date - od.order_purchase_timestamp)) / 86400.0
      AS days_purchase_to_delivery,
    GREATEST(
      EXTRACT(EPOCH FROM (od.order_delivered_customer_date - od.order_estimated_delivery_date)) / 86400.0,
      0
    ) AS days_late
  FROM analytics.vw_order_delivery od
  JOIN customers c ON c.customer_id = od.customer_id
  WHERE od.order_delivered_customer_date IS NOT NULL
    AND od.order_estimated_delivery_date IS NOT NULL
)
SELECT
  month_name,
  customer_state,
  COUNT(*) AS delivered_orders,
  ROUND(100.0 * AVG(is_on_time), 2) AS on_time_rate_pct,
  ROUND(AVG(NULLIF(days_late, 0)), 2) AS avg_days_late_when_late,
  ROUND(AVG(days_purchase_to_delivery), 2) AS avg_days_purchase_to_delivery
FROM delivered
GROUP BY 1, 2
HAVING COUNT(*) >= 50         
ORDER BY month_name, delivered_orders DESC;
--Business Use: This query measures logistics reliability: How often are orders delivered on or before the estimated date, and how does that vary by month and state--


--Query 7: Monthly revenue + orders + AOV + running total--
WITH monthly AS (
  SELECT
      TO_CHAR(order_purchase_timestamp, 'MONTH') AS month,
      COUNT(DISTINCT order_id) AS orders,
      SUM(order_gmv) AS revenue,
      ROUND(SUM(order_gmv) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS aov
  FROM analytics.vw_order_summary
  WHERE order_status IN ('delivered', 'shipped', 'invoiced', 'approved')
  GROUP BY month
)
SELECT
    month,
    orders,
    revenue,
    aov,
    SUM(revenue) OVER (ORDER BY month) AS running_revenue
FROM monthly
ORDER BY month;
--Business Use: This query creates a monthly performance table plus a running total.--
--It answers: How is the business growing over time, and what is the cumulative revenue so far?--
