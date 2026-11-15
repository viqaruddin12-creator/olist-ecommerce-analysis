
SELECT *
FROM olist_combined_dataset
LIMIT 10;

-- TASK 02: Count the total rows in the flattened dataset
SELECT COUNT(*) AS total_rows
FROM olist_combined_dataset;

-- TASK 03: Count distinct orders
SELECT COUNT(DISTINCT order_id) AS total_orders
FROM olist_combined_dataset;

-- TASK 04: Count orders by order status
SELECT
    order_status,
    COUNT(DISTINCT order_id) AS total_orders
FROM olist_combined_dataset
GROUP BY order_status
ORDER BY total_orders DESC;

-- TASK 05: Monthly order count
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
    COUNT(DISTINCT order_id) AS total_orders
FROM olist_combined_dataset
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY purchase_month;

-- TASK 06: Identify order IDs appearing on multiple rows.
-- Multiple rows are expected in this flattened dataset; this is
-- a grain diagnostic, not proof of duplicate source orders.
SELECT
    order_id,
    COUNT(*) AS row_count
FROM olist_combined_dataset
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 50;

-- TASK 07: Count missing values in key order columns
SELECT
    SUM(order_id IS NULL) AS missing_order_id,
    SUM(customer_id IS NULL) AS missing_customer_id,
    SUM(order_status IS NULL) AS missing_order_status,
    SUM(order_purchase_timestamp IS NULL) AS missing_purchase_timestamp
FROM olist_combined_dataset;

-- TASK 08: Count orders missing delivery milestone dates
SELECT
    COUNT(DISTINCT CASE
        WHEN order_delivered_carrier_date IS NULL THEN order_id END
    ) AS orders_missing_carrier_date,
    COUNT(DISTINCT CASE
        WHEN order_delivered_customer_date IS NULL THEN order_id END
    ) AS orders_missing_customer_delivery_date,
    COUNT(DISTINCT CASE
        WHEN order_estimated_delivery_date IS NULL THEN order_id END
    ) AS orders_missing_estimated_delivery_date
FROM olist_combined_dataset;

-- TASK 09: Find products with missing product category
SELECT DISTINCT
    product_id,
    product_category_name
FROM olist_combined_dataset
WHERE product_category_name IS NULL;

-- TASK 10: Calculate average order value using item price only.
-- First reduce the flattened rows to one row per order item.
SELECT
    ROUND(AVG(order_revenue), 2) AS average_order_value
FROM (
    SELECT
        order_id,
        SUM(price) AS order_revenue
    FROM (
        SELECT DISTINCT order_id, order_item_id, price
        FROM olist_combined_dataset
        WHERE order_id IS NOT NULL
          AND order_item_id IS NOT NULL
    ) AS unique_items
    GROUP BY order_id
) AS order_totals;

-- TASK 11: Find repeat customers (more than one distinct order)
SELECT
    customer_unique_id,
    COUNT(DISTINCT order_id) AS order_count
FROM olist_combined_dataset
WHERE customer_unique_id IS NOT NULL
GROUP BY customer_unique_id
HAVING COUNT(DISTINCT order_id) > 1
ORDER BY order_count DESC;

-- TASK 12: Compare average review score by payment type.
-- A review is associated with each payment type used on its order;
-- multi-payment orders can therefore appear under multiple types.
WITH order_reviews AS (
    SELECT order_id, review_id, review_score
    FROM (
        SELECT DISTINCT order_id, review_id, review_score
        FROM olist_combined_dataset
        WHERE review_id IS NOT NULL
    ) r
),
order_payment_types AS (
    SELECT DISTINCT order_id, payment_type
    FROM olist_combined_dataset
    WHERE payment_type IS NOT NULL
)
SELECT
    p.payment_type,
    COUNT(DISTINCT r.review_id) AS review_count,
    ROUND(AVG(r.review_score), 2) AS average_review_score
FROM order_payment_types p
JOIN order_reviews r ON p.order_id = r.order_id
GROUP BY p.payment_type
ORDER BY average_review_score DESC;

-- TASK 13: Business summary — orders, item revenue, average review score.
-- Each metric is aggregated at its own grain before joining.
WITH item_totals AS (
    SELECT order_id, SUM(price) AS item_revenue
    FROM (
        SELECT DISTINCT order_id, order_item_id, price
        FROM olist_combined_dataset
        WHERE order_id IS NOT NULL AND order_item_id IS NOT NULL
    ) i
    GROUP BY order_id
),
order_reviews AS (
    SELECT order_id, AVG(review_score) AS order_review_score
    FROM (
        SELECT DISTINCT order_id, review_id, review_score
        FROM olist_combined_dataset
        WHERE review_id IS NOT NULL
    ) r
    GROUP BY order_id
),
order_base AS (
    SELECT DISTINCT order_id, order_status
    FROM olist_combined_dataset
)
SELECT
    COUNT(DISTINCT b.order_id) AS total_orders,
    ROUND(SUM(i.item_revenue), 2) AS total_item_revenue,
    ROUND(AVG(r.order_review_score), 2) AS average_order_review_score
FROM order_base b
LEFT JOIN item_totals i ON b.order_id = i.order_id
LEFT JOIN order_reviews r ON b.order_id = r.order_id;

-- TASK 14: Total item revenue by English product category
SELECT
    category,
    ROUND(SUM(item_revenue), 2) AS category_revenue
FROM (
    SELECT
        product_category_name_english AS category,
        order_id,
        order_item_id,
        MAX(price) AS item_revenue
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
    GROUP BY product_category_name_english, order_id, order_item_id
) items
GROUP BY category
ORDER BY category_revenue DESC;

-- TASK 15: Top 10 product categories by item revenue
SELECT
    category,
    ROUND(SUM(item_revenue), 2) AS category_revenue
FROM (
    SELECT
        product_category_name_english AS category,
        order_id,
        order_item_id,
        MAX(price) AS item_revenue
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
    GROUP BY product_category_name_english, order_id, order_item_id
) items
GROUP BY category
ORDER BY category_revenue DESC
LIMIT 10;

-- TASK 16: Revenue by customer state
SELECT
    customer_state,
    ROUND(SUM(item_revenue), 2) AS item_revenue
FROM (
    SELECT
        order_id,
        customer_state,
        order_item_id,
        MAX(price) AS item_revenue
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
    GROUP BY order_id, customer_state, order_item_id
) items
GROUP BY customer_state
ORDER BY item_revenue DESC;

-- TASK 17: Revenue by payment type using payment values.
-- Deduplicate payment records at (order_id, payment_sequential).
SELECT
    payment_type,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM (
    SELECT
        order_id,
        payment_sequential,
        payment_type,
        MAX(payment_value) AS payment_value
    FROM olist_combined_dataset
    WHERE payment_sequential IS NOT NULL
    GROUP BY order_id, payment_sequential, payment_type
) payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- TASK 18: Revenue contribution percentage by product category
WITH category_revenue AS (
    SELECT
        product_category_name_english AS category,
        SUM(item_revenue) AS revenue
    FROM (
        SELECT
            product_category_name_english,
            order_id,
            order_item_id,
            MAX(price) AS item_revenue
        FROM olist_combined_dataset
        WHERE order_item_id IS NOT NULL
        GROUP BY product_category_name_english, order_id, order_item_id
    ) x
    GROUP BY product_category_name_english
)
SELECT
    category,
    ROUND(revenue, 2) AS revenue,
    ROUND(100 * revenue / NULLIF(SUM(revenue) OVER (), 0), 2) AS revenue_pct
FROM category_revenue
ORDER BY revenue DESC;

-- TASK 19: Top 10 products by units sold
SELECT
    product_id,
    COUNT(*) AS units_sold
FROM (
    SELECT DISTINCT order_id, order_item_id, product_id
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
) x
GROUP BY product_id
ORDER BY units_sold DESC
LIMIT 10;

-- TASK 20: Top 10 products by item revenue
SELECT
    product_id,
    ROUND(SUM(item_price), 2) AS product_revenue
FROM (
    SELECT
        order_id,
        order_item_id,
        product_id,
        MAX(price) AS item_price
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
    GROUP BY order_id, order_item_id, product_id
) x
GROUP BY product_id
ORDER BY product_revenue DESC
LIMIT 10;

-- TASK 21: Count orders by customer state
SELECT
    customer_state,
    COUNT(DISTINCT order_id) AS total_orders
FROM olist_combined_dataset
GROUP BY customer_state
ORDER BY total_orders DESC;

-- TASK 22: Count unique customers by state
SELECT
    customer_state,
    COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM olist_combined_dataset
GROUP BY customer_state
ORDER BY unique_customers DESC;

-- TASK 23: Find the top 10 cities by number of orders
SELECT
    customer_city,
    customer_state,
    COUNT(DISTINCT order_id) AS total_orders
FROM olist_combined_dataset
GROUP BY customer_city, customer_state
ORDER BY total_orders DESC
LIMIT 10;

-- TASK 24: Calculate repeat-customer percentage
WITH customer_order_counts AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM olist_combined_dataset
    WHERE customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS total_unique_customers,
    SUM(order_count > 1) AS repeat_customers,
    ROUND(100 * SUM(order_count > 1) / NULLIF(COUNT(*), 0), 2)
        AS repeat_customer_percentage
FROM customer_order_counts;

-- TASK 25: Find customers with the highest lifetime item spend
WITH item_rows AS (
    SELECT
        order_id,
        customer_unique_id,
        order_item_id,
        MAX(price) AS item_price
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
    GROUP BY order_id, customer_unique_id, order_item_id
)
SELECT
    customer_unique_id,
    ROUND(SUM(item_price), 2) AS lifetime_item_spend
FROM item_rows
GROUP BY customer_unique_id
ORDER BY lifetime_item_spend DESC
LIMIT 10;

-- TASK 26: Calculate average delivery time in days
WITH order_dates AS (
    SELECT
        order_id,
        MAX(order_purchase_timestamp) AS purchase_ts,
        MAX(order_delivered_customer_date) AS delivered_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    ROUND(AVG(TIMESTAMPDIFF(DAY, purchase_ts, delivered_ts)), 2)
        AS average_delivery_days
FROM order_dates
WHERE purchase_ts IS NOT NULL AND delivered_ts IS NOT NULL;

-- TASK 27: Count on-time and late delivered orders
WITH order_dates AS (
    SELECT
        order_id,
        MAX(order_delivered_customer_date) AS delivered_ts,
        MAX(order_estimated_delivery_date) AS estimated_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    SUM(delivered_ts <= estimated_ts) AS on_time_orders,
    SUM(delivered_ts > estimated_ts) AS late_orders
FROM order_dates
WHERE delivered_ts IS NOT NULL AND estimated_ts IS NOT NULL;

-- TASK 28: Calculate on-time delivery percentage
WITH order_dates AS (
    SELECT
        order_id,
        MAX(order_delivered_customer_date) AS delivered_ts,
        MAX(order_estimated_delivery_date) AS estimated_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    ROUND(
        100 * SUM(delivered_ts <= estimated_ts) / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_delivery_percentage
FROM order_dates
WHERE delivered_ts IS NOT NULL AND estimated_ts IS NOT NULL;

-- TASK 29: Late deliveries by customer state
WITH order_dates AS (
    SELECT
        order_id,
        MAX(customer_state) AS customer_state,
        MAX(order_delivered_customer_date) AS delivered_ts,
        MAX(order_estimated_delivery_date) AS estimated_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    customer_state,
    COUNT(*) AS late_deliveries
FROM order_dates
WHERE delivered_ts IS NOT NULL
  AND estimated_ts IS NOT NULL
  AND delivered_ts > estimated_ts
GROUP BY customer_state
ORDER BY late_deliveries DESC;

-- TASK 30: Monthly on-time delivery percentage
WITH order_dates AS (
    SELECT
        order_id,
        MAX(order_purchase_timestamp) AS purchase_ts,
        MAX(order_delivered_customer_date) AS delivered_ts,
        MAX(order_estimated_delivery_date) AS estimated_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    DATE_FORMAT(purchase_ts, '%Y-%m') AS purchase_month,
    ROUND(
        100 * SUM(delivered_ts <= estimated_ts) / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_delivery_pct
FROM order_dates
WHERE purchase_ts IS NOT NULL
  AND delivered_ts IS NOT NULL
  AND estimated_ts IS NOT NULL
GROUP BY DATE_FORMAT(purchase_ts, '%Y-%m')
ORDER BY purchase_month;

-- TASK 31: Average delivery days by seller.
-- Each order-item is attributed to its seller; multi-seller orders
-- can have the same order delivery duration under multiple sellers.
WITH order_delivery AS (
    SELECT
        order_id,
        MAX(order_purchase_timestamp) AS purchase_ts,
        MAX(order_delivered_customer_date) AS delivered_ts
    FROM olist_combined_dataset
    GROUP BY order_id
),
seller_order_items AS (
    SELECT DISTINCT order_id, seller_id, order_item_id
    FROM olist_combined_dataset
    WHERE seller_id IS NOT NULL AND order_item_id IS NOT NULL
)
SELECT
    s.seller_id,
    ROUND(AVG(TIMESTAMPDIFF(DAY, d.purchase_ts, d.delivered_ts)), 2)
        AS average_delivery_days
FROM seller_order_items s
JOIN order_delivery d ON s.order_id = d.order_id
WHERE d.purchase_ts IS NOT NULL AND d.delivered_ts IS NOT NULL
GROUP BY s.seller_id
ORDER BY average_delivery_days;

-- TASK 32: Compare average review score for on-time vs late orders
WITH order_dates AS (
    SELECT
        order_id,
        MAX(order_delivered_customer_date) AS delivered_ts,
        MAX(order_estimated_delivery_date) AS estimated_ts
    FROM olist_combined_dataset
    GROUP BY order_id
),
order_reviews AS (
    SELECT order_id, review_id, review_score
    FROM (
        SELECT DISTINCT order_id, review_id, review_score
        FROM olist_combined_dataset
        WHERE review_id IS NOT NULL
    ) x
)
SELECT
    CASE
        WHEN d.delivered_ts <= d.estimated_ts THEN 'On Time'
        WHEN d.delivered_ts > d.estimated_ts THEN 'Late'
    END AS delivery_status,
    ROUND(AVG(r.review_score), 2) AS average_review_score,
    COUNT(DISTINCT r.review_id) AS review_count
FROM order_dates d
JOIN order_reviews r ON d.order_id = r.order_id
WHERE d.delivered_ts IS NOT NULL AND d.estimated_ts IS NOT NULL
GROUP BY delivery_status;

-- TASK 33: Review score distribution
SELECT
    review_score,
    COUNT(DISTINCT review_id) AS review_count
FROM olist_combined_dataset
WHERE review_id IS NOT NULL
GROUP BY review_score
ORDER BY review_score;

-- TASK 34: Percentage of positive reviews (score 4 or 5)
WITH reviews AS (
    SELECT DISTINCT review_id, review_score
    FROM olist_combined_dataset
    WHERE review_id IS NOT NULL
)
SELECT
    ROUND(
        100 * SUM(review_score >= 4) / NULLIF(COUNT(*), 0),
        2
    ) AS positive_review_percentage
FROM reviews;

-- TASK 35: Average review score by product category.
-- Each review is linked to the category/categories in its order.
WITH review_categories AS (
    SELECT DISTINCT
        order_id,
        review_id,
        review_score,
        product_category_name_english
    FROM olist_combined_dataset
    WHERE review_id IS NOT NULL
      AND product_category_name_english IS NOT NULL
)
SELECT
    product_category_name_english,
    ROUND(AVG(review_score), 2) AS average_review_score,
    COUNT(DISTINCT review_id) AS review_count
FROM review_categories
GROUP BY product_category_name_english
ORDER BY average_review_score DESC;

-- TASK 36: Review count by payment type
WITH reviews AS (
    SELECT DISTINCT order_id, review_id, review_score
    FROM olist_combined_dataset
    WHERE review_id IS NOT NULL
),
payment_types AS (
    SELECT DISTINCT order_id, payment_type
    FROM olist_combined_dataset
    WHERE payment_type IS NOT NULL
)
SELECT
    p.payment_type,
    COUNT(DISTINCT r.review_id) AS review_count
FROM payment_types p
JOIN reviews r ON p.order_id = r.order_id
GROUP BY p.payment_type
ORDER BY review_count DESC;

-- TASK 37: Count payment records by payment type
SELECT
    payment_type,
    COUNT(*) AS payment_record_count
FROM (
    SELECT DISTINCT order_id, payment_sequential, payment_type
    FROM olist_combined_dataset
    WHERE payment_sequential IS NOT NULL
) p
GROUP BY payment_type
ORDER BY payment_record_count DESC;

-- TASK 38: Average number of installments by payment type
SELECT
    payment_type,
    ROUND(AVG(payment_installments), 2) AS average_installments
FROM (
    SELECT
        order_id,
        payment_sequential,
        payment_type,
        MAX(payment_installments) AS payment_installments
    FROM olist_combined_dataset
    WHERE payment_sequential IS NOT NULL
    GROUP BY order_id, payment_sequential, payment_type
) p
GROUP BY payment_type
ORDER BY average_installments DESC;

-- TASK 39: Average freight value by customer state at item grain
SELECT
    customer_state,
    ROUND(AVG(freight_value), 2) AS average_freight_per_item
FROM (
    SELECT DISTINCT
        order_id, order_item_id, customer_state, freight_value
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
) x
GROUP BY customer_state
ORDER BY average_freight_per_item DESC;

-- TASK 40: Find orders with total item price above R$ 1,000
SELECT
    order_id,
    ROUND(SUM(price), 2) AS order_item_total
FROM (
    SELECT DISTINCT order_id, order_item_id, price
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
) x
GROUP BY order_id
HAVING SUM(price) > 1000
ORDER BY order_item_total DESC;

-- TASK 41: Rank product categories by revenue using a window function
WITH category_revenue AS (
    SELECT
        product_category_name_english AS category,
        SUM(item_price) AS revenue
    FROM (
        SELECT
            order_id,
            order_item_id,
            product_category_name_english,
            MAX(price) AS item_price
        FROM olist_combined_dataset
        WHERE order_item_id IS NOT NULL
        GROUP BY order_id, order_item_id, product_category_name_english
    ) x
    GROUP BY product_category_name_english
)
SELECT
    category,
    ROUND(revenue, 2) AS revenue,
    DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM category_revenue
ORDER BY revenue_rank;

-- TASK 42: Calculate cumulative monthly item revenue
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
        SUM(item_price) AS revenue
    FROM (
        SELECT
            order_id,
            order_item_id,
            MAX(order_purchase_timestamp) AS order_purchase_timestamp,
            MAX(price) AS item_price
        FROM olist_combined_dataset
        WHERE order_item_id IS NOT NULL
        GROUP BY order_id, order_item_id
    ) x
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
)
SELECT
    purchase_month,
    ROUND(revenue, 2) AS monthly_revenue,
    ROUND(SUM(revenue) OVER (ORDER BY purchase_month), 2)
        AS cumulative_revenue
FROM monthly_revenue
ORDER BY purchase_month;

-- TASK 43: Find month-over-month revenue change
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
        SUM(item_price) AS revenue
    FROM (
        SELECT
            order_id,
            order_item_id,
            MAX(order_purchase_timestamp) AS order_purchase_timestamp,
            MAX(price) AS item_price
        FROM olist_combined_dataset
        WHERE order_item_id IS NOT NULL
        GROUP BY order_id, order_item_id
    ) x
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
),
with_previous AS (
    SELECT
        purchase_month,
        revenue,
        LAG(revenue) OVER (ORDER BY purchase_month) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    purchase_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(previous_month_revenue, 2) AS previous_month_revenue,
    ROUND(revenue - previous_month_revenue, 2) AS revenue_change,
    ROUND(
        100 * (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0),
        2
    ) AS revenue_change_pct
FROM with_previous
ORDER BY purchase_month;

-- TASK 44: Rank sellers by item revenue
SELECT
    seller_id,
    ROUND(SUM(item_price), 2) AS seller_revenue,
    DENSE_RANK() OVER (ORDER BY SUM(item_price) DESC) AS seller_rank
FROM (
    SELECT
        order_id,
        order_item_id,
        seller_id,
        MAX(price) AS item_price
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
    GROUP BY order_id, order_item_id, seller_id
) x
GROUP BY seller_id
ORDER BY seller_rank
LIMIT 20;

-- TASK 45: Count distinct products in each category
SELECT
    product_category_name_english,
    COUNT(DISTINCT product_id) AS distinct_products
FROM olist_combined_dataset
GROUP BY product_category_name_english
ORDER BY distinct_products DESC;

-- TASK 46: Average product weight by category
SELECT
    product_category_name_english,
    ROUND(AVG(product_weight_g), 2) AS average_product_weight_g
FROM (
    SELECT DISTINCT product_id, product_category_name_english, product_weight_g
    FROM olist_combined_dataset
    WHERE product_id IS NOT NULL
) p
GROUP BY product_category_name_english
ORDER BY average_product_weight_g DESC;

-- TASK 47: Compare item price and freight by category
SELECT
    product_category_name_english,
    ROUND(AVG(price), 2) AS average_item_price,
    ROUND(AVG(freight_value), 2) AS average_freight_value
FROM (
    SELECT DISTINCT
        order_id, order_item_id, product_category_name_english,
        price, freight_value
    FROM olist_combined_dataset
    WHERE order_item_id IS NOT NULL
) x
GROUP BY product_category_name_english
ORDER BY average_item_price DESC;

-- TASK 48: Calculate order approval time in hours
WITH order_times AS (
    SELECT
        order_id,
        MAX(order_purchase_timestamp) AS purchase_ts,
        MAX(order_approved_at) AS approved_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    ROUND(AVG(TIMESTAMPDIFF(HOUR, purchase_ts, approved_ts)), 2)
        AS average_approval_hours
FROM order_times
WHERE purchase_ts IS NOT NULL AND approved_ts IS NOT NULL;

-- TASK 49: Calculate time from purchase to carrier handoff in hours
WITH order_times AS (
    SELECT
        order_id,
        MAX(order_purchase_timestamp) AS purchase_ts,
        MAX(order_delivered_carrier_date) AS carrier_ts
    FROM olist_combined_dataset
    GROUP BY order_id
)
SELECT
    ROUND(AVG(TIMESTAMPDIFF(HOUR, purchase_ts, carrier_ts)), 2)
        AS average_hours_to_carrier
FROM order_times
WHERE purchase_ts IS NOT NULL AND carrier_ts IS NOT NULL;

-- TASK 50: Create a consolidated monthly KPI report
-- Metrics are calculated at their correct grain before joining.
WITH monthly_orders AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
        COUNT(DISTINCT order_id) AS total_orders
    FROM olist_combined_dataset
    WHERE order_purchase_timestamp IS NOT NULL
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
),
monthly_item_revenue AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
        SUM(item_price) AS item_revenue
    FROM (
        SELECT
            order_id,
            order_item_id,
            MAX(order_purchase_timestamp) AS order_purchase_timestamp,
            MAX(price) AS item_price
        FROM olist_combined_dataset
        WHERE order_item_id IS NOT NULL
        GROUP BY order_id, order_item_id
    ) x
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
),
monthly_reviews AS (
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
        AVG(review_score) AS average_review_score
    FROM (
        SELECT DISTINCT
            order_id,
            MAX(order_purchase_timestamp) OVER (PARTITION BY order_id)
                AS order_purchase_timestamp,
            review_id,
            review_score
        FROM olist_combined_dataset
        WHERE review_id IS NOT NULL
    ) r
    GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
)
SELECT
    o.purchase_month,
    o.total_orders,
    ROUND(r.item_revenue, 2) AS item_revenue,
    ROUND(r.item_revenue / NULLIF(o.total_orders, 0), 2) AS average_order_value,
    ROUND(v.average_review_score, 2) AS average_review_score
FROM monthly_orders o
LEFT JOIN monthly_item_revenue r
    ON o.purchase_month = r.purchase_month
LEFT JOIN monthly_reviews v
    ON o.purchase_month = v.purchase_month
ORDER BY o.purchase_month;
