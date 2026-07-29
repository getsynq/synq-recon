-- ETL pipeline validation: operational and reporting sales tables
-- Covers two weeks of daily sales across two stores.

-- Operational database: daily sales records (source of truth)
CREATE OR REPLACE TABLE operational_sales AS
SELECT * FROM (VALUES
  -- Week 1
  (DATE '2024-01-15', 1,  'STORE_A', 125.50, 3),
  (DATE '2024-01-15', 2,  'STORE_A', 75.00,  1),
  (DATE '2024-01-15', 3,  'STORE_B', 200.00, 5),
  (DATE '2024-01-15', 4,  'STORE_B', 150.75, 2),
  (DATE '2024-01-16', 5,  'STORE_A', 300.00, 4),
  (DATE '2024-01-16', 6,  'STORE_A', 99.99,  2),
  (DATE '2024-01-16', 7,  'STORE_B', 175.50, 3),
  (DATE '2024-01-16', 8,  'STORE_B', 225.00, 6),
  (DATE '2024-01-17', 9,  'STORE_A', 450.00, 8),
  (DATE '2024-01-17', 10, 'STORE_A', 180.25, 3),
  (DATE '2024-01-17', 11, 'STORE_B', 320.00, 5),
  (DATE '2024-01-17', 12, 'STORE_B', 275.50, 4),
  (DATE '2024-01-18', 13, 'STORE_A', 89.99,  2),
  (DATE '2024-01-18', 14, 'STORE_B', 410.00, 7),
  (DATE '2024-01-19', 15, 'STORE_A', 55.00,  1),
  (DATE '2024-01-19', 16, 'STORE_A', 330.00, 6),
  (DATE '2024-01-19', 17, 'STORE_B', 145.75, 3),
  -- Week 2 (no weekend sales)
  (DATE '2024-01-22', 18, 'STORE_A', 210.00, 4),
  (DATE '2024-01-22', 19, 'STORE_B', 185.50, 3),
  (DATE '2024-01-23', 20, 'STORE_A', 95.00,  2),
  (DATE '2024-01-23', 21, 'STORE_A', 420.00, 7),
  (DATE '2024-01-23', 22, 'STORE_B', 160.25, 3),
  (DATE '2024-01-24', 23, 'STORE_A', 275.00, 5),
  (DATE '2024-01-24', 24, 'STORE_B', 340.00, 6),
  (DATE '2024-01-24', 25, 'STORE_B', 88.50,  1),
  (DATE '2024-01-25', 26, 'STORE_A', 190.00, 3),
  (DATE '2024-01-25', 27, 'STORE_B', 505.00, 9),
  (DATE '2024-01-26', 28, 'STORE_A', 120.00, 2),
  (DATE '2024-01-26', 29, 'STORE_A', 375.00, 6),
  (DATE '2024-01-26', 30, 'STORE_B', 260.00, 4)
) AS sales(sale_date, sale_id, store_id, amount, quantity);

-- Reporting database: ETL output (with errors in both weeks)
CREATE OR REPLACE TABLE reporting_sales AS
SELECT * FROM (VALUES
  -- Week 1: wrong amount on Jan 16, missing row on Jan 17
  (DATE '2024-01-15', 1,  'STORE_A', 125.50, 3),
  (DATE '2024-01-15', 2,  'STORE_A', 75.00,  1),
  (DATE '2024-01-15', 3,  'STORE_B', 200.00, 5),
  (DATE '2024-01-15', 4,  'STORE_B', 150.75, 2),
  (DATE '2024-01-16', 5,  'STORE_A', 300.00, 4),
  (DATE '2024-01-16', 6,  'STORE_A', 99.99,  2),
  (DATE '2024-01-16', 7,  'STORE_B', 175.50, 3),
  (DATE '2024-01-16', 8,  'STORE_B', 999.99, 6),  -- Wrong amount: $225 -> $999.99
  (DATE '2024-01-17', 9,  'STORE_A', 450.00, 8),
  (DATE '2024-01-17', 10, 'STORE_A', 180.25, 3),
  (DATE '2024-01-17', 11, 'STORE_B', 320.00, 5),
  -- Missing sale_id=12 ($275.50)
  (DATE '2024-01-18', 13, 'STORE_A', 89.99,  2),
  (DATE '2024-01-18', 14, 'STORE_B', 410.00, 7),
  (DATE '2024-01-19', 15, 'STORE_A', 55.00,  1),
  (DATE '2024-01-19', 16, 'STORE_A', 330.00, 6),
  (DATE '2024-01-19', 17, 'STORE_B', 145.75, 3),
  -- Week 2: wrong quantity on Jan 24
  (DATE '2024-01-22', 18, 'STORE_A', 210.00, 4),
  (DATE '2024-01-22', 19, 'STORE_B', 185.50, 3),
  (DATE '2024-01-23', 20, 'STORE_A', 95.00,  2),
  (DATE '2024-01-23', 21, 'STORE_A', 420.00, 7),
  (DATE '2024-01-23', 22, 'STORE_B', 160.25, 3),
  (DATE '2024-01-24', 23, 'STORE_A', 275.00, 5),
  (DATE '2024-01-24', 24, 'STORE_B', 340.00, 6),
  (DATE '2024-01-24', 25, 'STORE_B', 88.50,  99), -- Wrong quantity: 1 -> 99
  (DATE '2024-01-25', 26, 'STORE_A', 190.00, 3),
  (DATE '2024-01-25', 27, 'STORE_B', 505.00, 9),
  (DATE '2024-01-26', 28, 'STORE_A', 120.00, 2),
  (DATE '2024-01-26', 29, 'STORE_A', 375.00, 6),
  (DATE '2024-01-26', 30, 'STORE_B', 260.00, 4)
) AS sales(sale_date, sale_id, store_id, amount, quantity);
