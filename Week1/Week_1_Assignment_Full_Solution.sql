-- Voltkart Session 1 — Full assignment solution (T-SQL)
-- Database: TrainingCBDB
-- Q8 and Q9 change data. Run those once.

USE TrainingCBDB;
GO

/* =============================================================================
   WARM-UP
   ============================================================================= */

-- Query #1
-- Hint: fact_orders, dim_customer, dim_employee. INNER JOINs, WHERE on status, TOP, ORDER BY.

SELECT TOP 20
       f.order_id,
       f.order_date,
       c.customer_name,
       e.employee_name AS sales_rep_name,
       f.order_total
FROM fact_orders f
INNER JOIN dim_employee e ON f.sales_rep_id = e.employee_id
INNER JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE f.order_status = 'Completed'
ORDER BY f.order_total DESC;


-- Query #2
-- Hint: dim_customer, fact_orders. Anti-join with NOT EXISTS.

SELECT c.customer_id,
       c.customer_name,
       c.signup_date
FROM dim_customer c
WHERE NOT EXISTS (
    SELECT 1
    FROM fact_orders o
    WHERE o.customer_id = c.customer_id
);


-- Query #3
-- Hint: SUM(line_amount); RANK() OVER (PARTITION BY category ORDER BY revenue DESC); filter rank <= 3.

;WITH Result1 AS (
    SELECT cat.category_name,
           p.product_name,
           SUM(oi.line_amount) AS total_revenue
    FROM dim_product p
    INNER JOIN dim_category cat ON p.category_id = cat.category_id
    INNER JOIN fact_order_items oi ON p.product_id = oi.product_id
    INNER JOIN fact_orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'Completed'
    GROUP BY cat.category_name, p.product_name
),
RankResult AS (
    SELECT *,
           RANK() OVER (PARTITION BY category_name ORDER BY total_revenue DESC) AS revenue_rank
    FROM Result1
)
SELECT category_name,
       product_name,
       total_revenue,
       revenue_rank
FROM RankResult
WHERE revenue_rank <= 3
ORDER BY category_name, revenue_rank, product_name;


/* =============================================================================
   CORE
   ============================================================================= */

-- Query #4
-- Hint: CONVERT(char(7), order_date, 126); SUM() OVER for running total; LAG() for MoM %.

;WITH monthly AS (
    SELECT CONVERT(char(7), order_date, 126) AS order_month,
           SUM(order_total) AS monthly_revenue
    FROM fact_orders
    WHERE order_status = 'Completed'
    GROUP BY CONVERT(char(7), order_date, 126)
)
SELECT order_month,
       monthly_revenue,
       SUM(monthly_revenue) OVER (ORDER BY order_month ROWS UNBOUNDED PRECEDING) AS running_total,
       CAST(
           (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY order_month)) * 100.0
           / NULLIF(LAG(monthly_revenue) OVER (ORDER BY order_month), 0)
           AS DECIMAL(10, 2)
       ) AS mom_pct_change
FROM monthly
ORDER BY order_month;


-- Query #5
-- Hint: per-customer SUM, NTILE(4) OVER (ORDER BY spend), GROUP BY quartile.

;WITH customer_spend AS (
    SELECT customer_id,
           SUM(order_total) AS lifetime_spend
    FROM fact_orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
),
quartiles AS (
    SELECT lifetime_spend,
           NTILE(4) OVER (ORDER BY lifetime_spend) AS spend_quartile
    FROM customer_spend
)
SELECT spend_quartile,
       COUNT(*) AS customer_count,
       CAST(AVG(lifetime_spend) AS DECIMAL(18, 2)) AS avg_lifetime_spend
FROM quartiles
GROUP BY spend_quartile
ORDER BY spend_quartile;


-- Query #6
-- Hint: recursive CTE — anchor at 'Computers', recurse on parent_category_id; depth + path.
-- CSV load left CHAR(13) on category_name, so REPLACE is required for the name match.

;WITH category_tree AS (
    SELECT category_id,
           parent_category_id,
           REPLACE(category_name, CHAR(13), N'') AS category_name,
           0 AS depth_level,
           CAST(REPLACE(category_name, CHAR(13), N'') AS NVARCHAR(MAX)) AS category_path
    FROM dim_category
    WHERE REPLACE(category_name, CHAR(13), N'') = N'Computers'

    UNION ALL

    SELECT c.category_id,
           c.parent_category_id,
           REPLACE(c.category_name, CHAR(13), N''),
           t.depth_level + 1,
           CAST(t.category_path + N' > ' + REPLACE(c.category_name, CHAR(13), N'') AS NVARCHAR(MAX))
    FROM dim_category c
    INNER JOIN category_tree t ON c.parent_category_id = t.category_id
)
SELECT category_id,
       category_name,
       depth_level,
       category_path
FROM category_tree
ORDER BY category_path;


-- Query #7
-- Hint: recursive CTE enumerates each employee's subtree (including themselves),
--       attribute Sales Rep completed orders, SUM up the tree.

;WITH emp_tree AS (
    SELECT employee_id AS root_id,
           employee_id AS member_id
    FROM dim_employee

    UNION ALL

    SELECT t.root_id,
           e.employee_id
    FROM emp_tree t
    INNER JOIN dim_employee e ON e.manager_id = t.member_id
)
SELECT e.employee_id,
       e.employee_name,
       e.role,
       CAST(SUM(ISNULL(o.order_total, 0)) AS DECIMAL(18, 2)) AS team_total_revenue
FROM emp_tree t
INNER JOIN dim_employee e ON e.employee_id = t.root_id
LEFT JOIN fact_orders o
       ON o.sales_rep_id = t.member_id
      AND o.order_status = 'Completed'
GROUP BY e.employee_id, e.employee_name, e.role
ORDER BY team_total_revenue DESC, e.employee_id;


-- Query #8
-- Hint: MERGE … ON order_id; WHEN MATCHED UPDATE; WHEN NOT MATCHED BY TARGET INSERT.
-- Changes fact_orders. Expected: 30,000 → 30,500 rows (300 updates + 500 inserts).

SELECT COUNT(*) AS fact_orders_row_count_before
FROM fact_orders;

MERGE fact_orders AS t
USING stg_orders_incr AS s
ON t.order_id = s.order_id
WHEN MATCHED THEN
    UPDATE SET t.order_status = s.order_status,
               t.order_total  = s.order_total
WHEN NOT MATCHED BY TARGET THEN
    INSERT (order_id, order_date, customer_id, sales_rep_id, order_status, order_total)
    VALUES (s.order_id, s.order_date, s.customer_id, s.sales_rep_id, s.order_status, s.order_total);

SELECT COUNT(*) AS fact_orders_row_count_after
FROM fact_orders;

SELECT TOP 20
       f.order_id,
       f.order_date,
       f.order_status,
       f.order_total
FROM fact_orders f
INNER JOIN stg_orders_incr s ON s.order_id = f.order_id
ORDER BY f.order_id;


-- Query #9
-- Hint: MATCHED + U → UPDATE; MATCHED + D → DELETE; NOT MATCHED + I → INSERT.
-- Changes dim_product. Expected: 20 UPDATE, 5 DELETE, 10 INSERT.

DECLARE @cdc_actions TABLE (
    merge_action NVARCHAR(10),
    product_id   BIGINT
);

MERGE dim_product AS t
USING cdc_product_changes AS s
ON t.product_id = s.product_id
WHEN MATCHED AND s.operation = 'U' THEN
    UPDATE SET t.product_name = s.product_name,
               t.category_id  = s.category_id,
               t.unit_price   = s.unit_price,
               t.unit_cost    = s.unit_cost,
               t.launch_date  = s.launch_date
WHEN MATCHED AND s.operation = 'D' THEN
    DELETE
WHEN NOT MATCHED BY TARGET AND s.operation = 'I' THEN
    INSERT (product_id, product_name, category_id, unit_price, unit_cost, launch_date)
    VALUES (s.product_id, s.product_name, s.category_id, s.unit_price, s.unit_cost, s.launch_date)
OUTPUT $action, COALESCE(inserted.product_id, deleted.product_id)
INTO @cdc_actions (merge_action, product_id);

SELECT merge_action,
       COUNT(*) AS product_count
FROM @cdc_actions
GROUP BY merge_action
ORDER BY merge_action;

SELECT a.merge_action,
       a.product_id,
       p.product_name
FROM @cdc_actions a
LEFT JOIN dim_product p ON p.product_id = a.product_id
ORDER BY a.merge_action, a.product_id;


/* =============================================================================
   STRETCH
   ============================================================================= */

-- Query #10
-- Hint: SARGable date range (avoid YEAR on the column); pre-aggregated CTE instead of
--       correlated subquery; covering index with INCLUDE.
-- Also turn on Include Actual Execution Plan in SSMS.

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Original query from the assignment
SELECT o.customer_id,
       COUNT(*) AS orders_2024,
       (SELECT SUM(oi.line_amount)
        FROM fact_order_items oi
        JOIN fact_orders o2 ON o2.order_id = oi.order_id
        WHERE o2.customer_id = o.customer_id) AS lifetime_value
FROM fact_orders o
WHERE YEAR(o.order_date) = 2024
GROUP BY o.customer_id;

-- Rewritten query
;WITH orders_2024 AS (
    SELECT customer_id,
           COUNT(*) AS orders_2024
    FROM fact_orders
    WHERE order_date >= '2024-01-01'
      AND order_date <  '2025-01-01'
    GROUP BY customer_id
),
lifetime AS (
    SELECT o.customer_id,
           SUM(oi.line_amount) AS lifetime_value
    FROM fact_order_items oi
    INNER JOIN fact_orders o ON o.order_id = oi.order_id
    GROUP BY o.customer_id
)
SELECT a.customer_id,
       a.orders_2024,
       l.lifetime_value
FROM orders_2024 a
INNER JOIN lifetime l ON l.customer_id = a.customer_id;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

CREATE INDEX IX_fact_orders_order_date_incl_customer
ON fact_orders (order_date)
INCLUDE (customer_id);

CREATE INDEX IX_fact_order_items_order_id_incl_amount
ON fact_order_items (order_id)
INCLUDE (line_amount);

/*
  Q10 note (TrainingCBDB, SET STATISTICS IO, TIME):

  Original:
    fact_orders 498 logical reads, fact_order_items 415, CPU 47 ms, elapsed 139 ms
    YEAR(order_date) is not SARGable (scan). Correlated subquery repeats lifetime work.

  Rewritten before index:
    Same reads (498 / 415); CPU 31 ms, elapsed 105 ms — lifetime aggregated once, date range used.

  Rewritten + covering indexes:
    fact_orders 298 logical reads, fact_order_items 220, CPU 16 ms, elapsed 88 ms
    Range scan on order_date; INCLUDE covers customer_id and line_amount so lookups drop.
*/


-- Query #11 (Bonus)
-- Hint: gaps-and-islands — month as integer, subtract ROW_NUMBER() per customer, longest run.

;WITH active_months AS (
    SELECT DISTINCT
           customer_id,
           YEAR(order_date) * 12 + MONTH(order_date) AS month_num
    FROM fact_orders
    WHERE order_status = 'Completed'
),
islands AS (
    SELECT customer_id,
           month_num,
           month_num - ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY month_num) AS grp
    FROM active_months
),
streaks AS (
    SELECT customer_id,
           COUNT(*) AS streak_months
    FROM islands
    GROUP BY customer_id, grp
)
SELECT c.customer_id,
       c.customer_name,
       MAX(s.streak_months) AS longest_streak_months
FROM streaks s
INNER JOIN dim_customer c ON c.customer_id = s.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY longest_streak_months DESC, c.customer_id;
