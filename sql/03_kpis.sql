CREATE OR REPLACE VIEW analytics.vw_kpi_monthly AS
WITH base AS (
    SELECT
        date_trunc('month', order_purchase_timestamp)::date AS month_start,
        order_id,
        order_status,
        items_count,
        items_value,
        freight_value,
        order_gmv,
        payment_total,
        avg_review_score,
        review_count,
        days_puchase_to_delivery,
        days_early_or_late
    FROM analytics.vw_order_summary
    WHERE order_purchase_timestamp IS NOT NULL
),
agg AS (
    SELECT
        month_start,

        COUNT(DISTINCT order_id) AS orders,
        SUM(items_count) AS items,

        SUM(items_value) AS items_value,
        SUM(freight_value) AS freight_value,
        SUM(order_gmv) AS gmv,

        SUM(payment_total) AS payment_total,
        AVG(payment_total) AS avg_payment_per_order,

        AVG(avg_review_score) AS avg_review_score,
        SUM(review_count) AS reviews,

        AVG(days_puchase_to_delivery) AS avg_days_purchase_to_delivery,

        AVG(CASE WHEN days_early_or_late > interval '0 day' THEN 1.0 ELSE 0.0 END) AS pct_late_orders,

        COUNT(*) FILTER (WHERE order_status = 'delivered') AS delivered_orders,
        COUNT(*) FILTER (WHERE order_status <> 'delivered') AS not_delivered_orders
    FROM base
    GROUP BY month_start
),
final AS (
    SELECT
        month_start,
        orders,
        items,
        items_value,
        freight_value,
        gmv,
        payment_total,
        avg_payment_per_order,
        avg_review_score,
        reviews,
        avg_days_purchase_to_delivery,
        pct_late_orders,
        delivered_orders,
        not_delivered_orders,

        LAG(gmv) OVER (ORDER BY month_start) AS prev_month_gmv,
        LAG(orders) OVER (ORDER BY month_start) AS prev_month_orders
    FROM agg
)
SELECT
    month_start,
    orders,
    items,
    items_value,
    freight_value,
    gmv,
    payment_total,
    avg_payment_per_order,
    avg_review_score,
    reviews,
    avg_days_purchase_to_delivery,
    pct_late_orders,
    delivered_orders,
    not_delivered_orders,

    CASE
        WHEN prev_month_gmv IS NULL OR prev_month_gmv = 0 THEN NULL
        ELSE (gmv - prev_month_gmv) / prev_month_gmv
    END AS gmv_mom_pct,

    CASE
        WHEN prev_month_orders IS NULL OR prev_month_orders = 0 THEN NULL
        ELSE (orders - prev_month_orders)::numeric / prev_month_orders
    END AS orders_mom_pct
FROM final
ORDER BY month_start;
