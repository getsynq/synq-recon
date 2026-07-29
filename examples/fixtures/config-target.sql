-- Target tables for the production-ready reconciliation reference example
-- Simulates a data warehouse (Snowflake) with identical data for MATCH verification

-- 10K transactions (identical to source)
CREATE OR REPLACE TABLE transactions AS
SELECT
  CAST(id AS BIGINT) AS transaction_id,
  'CUST_' || CAST((id % 1000) AS VARCHAR) AS customer_id,
  CAST(id * 99.99 AS DECIMAL(18,2)) AS amount,
  CASE WHEN id % 3 = 0 THEN 'CREDIT' ELSE 'DEBIT' END AS transaction_type,
  DATE '2024-01-01' + CAST((id % 30) AS INTEGER) AS transaction_date
FROM generate_series(1, 10000) AS t(id);

-- Regional revenue (identical to source)
CREATE OR REPLACE TABLE regional_revenue AS
SELECT * FROM (VALUES
  ('NORTH', 1, 150000.00),
  ('NORTH', 2, 175000.00),
  ('SOUTH', 3, 125000.00),
  ('SOUTH', 4, 135000.00),
  ('EAST', 5, 200000.00),
  ('EAST', 6, 225000.00),
  ('WEST', 7, 180000.00),
  ('WEST', 8, 195000.00),
  ('NORTH', 9, 160000.00),
  ('SOUTH', 10, 140000.00)
) AS t(region, id, revenue);

-- 5K customers (identical to source)
CREATE OR REPLACE TABLE customers AS
SELECT
  CAST(id AS BIGINT) AS customer_id,
  'Customer ' || CAST(id AS VARCHAR) AS customer_name,
  'customer' || CAST(id AS VARCHAR) || '@example.com' AS email,
  CASE WHEN id % 2 = 0 THEN 'active' ELSE 'inactive' END AS status
FROM generate_series(1, 5000) AS t(id);

-- 1K orders with UPPERCASE column names (simulating Snowflake naming)
CREATE OR REPLACE TABLE orders AS
SELECT
  CAST(id AS BIGINT) AS ORDER_ID,
  id * 100.0 AS TOTAL_PAYMENT,
  'customer_' || CAST(id AS VARCHAR) AS CLIENT_NAME
FROM generate_series(1, 1000) AS t(id);
