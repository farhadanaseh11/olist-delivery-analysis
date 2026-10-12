-- Phase 1: How bad is delievery performance? 
SELECT
    COUNT(*) AS delivered_orders,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date > order_estimated_delivery_date
    ) AS late_orders,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE order_delivered_customer_date > order_estimated_delivery_date
        ) / COUNT(*),
        2
    ) AS late_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL; 

 -- Phase 2: Does lateness actually move review scores?
  
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 'Late'
        ELSE 'On time'
    END AS delivery_status,
    COUNT(*) AS orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 2) AS pct_1_or_2_star,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score = 5) / COUNT(*), 2) AS pct_5_star
FROM orders o --- going to the orders data table 
JOIN order_reviews r ON o.order_id = r.order_id 
WHERE o.order_status = 'delivered' 
  AND o.order_delivered_customer_date IS NOT null 
GROUP BY delivery_status; 


-- Phase 3: Where is the damage conentrated? (seller, category, region, time) If being late causes bad reviews does that mean more days late the worse a review gets?

SELECT
    CASE
        WHEN days_late <= 0 THEN 'On time or early'
        WHEN days_late <= 3 THEN '1-3 days late'
        WHEN days_late <= 7 THEN '4-7 days late'
        WHEN days_late <= 14 THEN '8-14 days late'
        ELSE '15+ days late'
    END AS lateness_bucket,
    COUNT(*) AS orders,
    ROUND(AVG(review_score), 2) AS avg_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS pct_1_2_star
FROM (
    SELECT
        DATE_PART('day', o.order_delivered_customer_date - o.order_estimated_delivery_date) AS days_late,
        r.review_score
    FROM orders o
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
) t
GROUP BY lateness_bucket
ORDER BY MIN(days_late);

--- Phase 3.1: Figuring out where the damage is concentrated. Is it Region, Time, Category, Seller?

SELECT items_per_order, COUNT(*) AS num_orders 
FROM (
    SELECT order_id, COUNT(*) AS items_per_order
    FROM order_items
    GROUP BY order_id
) t
GROUP BY items_per_order
ORDER BY items_per_order;

SELECT sellers_per_order, COUNT(*) AS num_orders 
FROM (
    SELECT order_id, COUNT(DISTINCT seller_id) AS sellers_per_order
    FROM order_items
    GROUP BY order_id
) t
GROUP BY sellers_per_order
ORDER BY sellers_per_order;

-- Phase 3.2 

WITH order_seller AS (
    SELECT order_id, MIN(seller_id) AS seller_id
    FROM order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
seller_stats AS (
    SELECT
        os.seller_id,
        COUNT(*) AS orders,
        ROUND(100.0 * COUNT(*) FILTER (
            WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date
        ) / COUNT(*), 2) AS late_pct,
        ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 2) AS bad_review_pct,
        COUNT(*) FILTER (WHERE r.review_score <= 2) AS bad_reviews
    FROM order_seller os
    JOIN orders o ON os.order_id = o.order_id
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY os.seller_id
    HAVING COUNT(*) >= 50
),
segmented AS (
    SELECT *,
        CASE
            WHEN late_pct >= 10 AND bad_review_pct >= 20 THEN 'Late and badly reviewed'
            WHEN late_pct >= 10 AND bad_review_pct <  20 THEN 'Late but forgiven'
            WHEN late_pct <  10 AND bad_review_pct >= 20 THEN 'On time but badly reviewed'
            ELSE 'Healthy'
        END AS seller_segment
    FROM seller_stats
)
SELECT
    seller_segment,
    COUNT(*) AS sellers,
    SUM(orders) AS total_orders,
    SUM(bad_reviews) AS total_bad_reviews,
    ROUND(100.0 * SUM(bad_reviews) / SUM(SUM(bad_reviews)) OVER (), 1) AS pct_of_bad_reviews
FROM segmented
GROUP BY seller_segment
ORDER BY total_bad_reviews DESC;

-- Late but forgiven query

WITH order_seller AS (
    SELECT order_id, MIN(seller_id) AS seller_id
    FROM order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
seller_stats AS (
    SELECT
        os.seller_id,
        COUNT(*) AS orders,
        ROUND(100.0 * COUNT(*) FILTER (
            WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date
        ) / COUNT(*), 2) AS late_pct,
        ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*), 2) AS bad_review_pct,
        ROUND(AVG(DATE_PART('day', o.order_estimated_delivery_date - o.order_purchase_timestamp))::numeric, 1) AS avg_promised_days,
        ROUND(AVG(DATE_PART('day', o.order_delivered_customer_date - o.order_purchase_timestamp))::numeric, 1) AS avg_actual_days,
        ROUND(AVG(DATE_PART('day', o.order_delivered_customer_date - o.order_estimated_delivery_date))
              FILTER (WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date)::numeric, 1) AS avg_days_late_when_late
    FROM order_seller os
    JOIN orders o ON os.order_id = o.order_id
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY os.seller_id
    HAVING COUNT(*) >= 50
)
SELECT
    CASE
        WHEN late_pct >= 10 AND bad_review_pct >= 20 THEN 'Late and badly reviewed'
        WHEN late_pct >= 10 AND bad_review_pct <  20 THEN 'Late but forgiven'
        WHEN late_pct <  10 AND bad_review_pct >= 20 THEN 'On time but badly reviewed'
        ELSE 'Healthy'
    END AS seller_segment,
    COUNT(*) AS sellers,
    ROUND(AVG(late_pct), 1) AS avg_late_pct,
    ROUND(AVG(bad_review_pct), 1) AS avg_bad_review_pct,
    ROUND(AVG(avg_promised_days), 1) AS promised_days,
    ROUND(AVG(avg_actual_days), 1) AS actual_days,
    ROUND(AVG(avg_promised_days - avg_actual_days), 1) AS avg_buffer_days,
    ROUND(AVG(avg_days_late_when_late), 1) AS days_late_when_late
FROM seller_stats
GROUP BY seller_segment
ORDER BY avg_bad_review_pct DESC;

-- Phase 4: What is the opportunity worth?
-- Benchmark: sellers above the median bad-review rate improve to the median.

WITH order_seller AS (
    SELECT order_id, MIN(seller_id) AS seller_id
    FROM order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
seller_stats AS (
    SELECT
        os.seller_id,
        COUNT(*) AS orders,
        COUNT(*) FILTER (WHERE r.review_score <= 2) AS bad_reviews,
        100.0 * COUNT(*) FILTER (WHERE r.review_score <= 2) / COUNT(*) AS bad_review_pct
    FROM order_seller os
    JOIN orders o ON os.order_id = o.order_id
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY os.seller_id
    HAVING COUNT(*) >= 50
),
benchmark AS (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY bad_review_pct) AS median_bad_pct
    FROM seller_stats
)
SELECT
    COUNT(*) AS sellers_above_median,
    SUM(s.orders) AS orders_affected,
    SUM(s.bad_reviews) AS current_bad_reviews,
    ROUND(SUM(s.orders * b.median_bad_pct / 100.0)::numeric) AS bad_reviews_if_at_median,
    ROUND((SUM(s.bad_reviews) - SUM(s.orders * b.median_bad_pct / 100.0))::numeric) AS recoverable_bad_reviews,
    ROUND(AVG(b.median_bad_pct)::numeric, 2) AS median_bad_review_pct
FROM seller_stats s
CROSS JOIN benchmark b
WHERE s.bad_review_pct > b.median_bad_pct;





