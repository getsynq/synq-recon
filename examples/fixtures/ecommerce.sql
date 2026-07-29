-- E-commerce reconciliation: payment gateway, warehouse, and inventory tables

-- Payment gateway: source of truth for orders
CREATE OR REPLACE TABLE payment_gateway_orders AS
SELECT * FROM (VALUES
  (CAST(1001 AS BIGINT), 'CUST001', DATE '2024-01-15', 159.99, 'paid', '123 Main St'),
  (1002, 'CUST002', DATE '2024-01-15', 249.50, 'paid', '456 Oak Ave'),
  (1003, 'CUST003', DATE '2024-01-16', 89.99, 'paid', '789 Pine Rd'),
  (1004, 'CUST001', DATE '2024-01-16', 199.99, 'paid', '123 Main St'),
  (1005, 'CUST004', DATE '2024-01-17', 329.00, 'paid', '321 Elm St'),
  (1006, 'CUST002', DATE '2024-01-17', 449.99, 'paid', '456 Oak Ave'),
  (1007, 'CUST005', DATE '2024-01-18', 99.99, 'paid', '654 Maple Dr'),
  (1008, 'CUST003', DATE '2024-01-18', 179.50, 'paid', '789 Pine Rd'),
  (1009, 'CUST006', DATE '2024-01-19', 599.99, 'paid', '987 Cedar Ln'),
  (1010, 'CUST004', DATE '2024-01-19', 129.99, 'paid', '321 Elm St')
) AS orders(order_id, customer_id, order_date, total_amount, payment_status, shipping_address);

-- Warehouse system: may lag behind or have data entry errors
CREATE OR REPLACE TABLE warehouse_orders AS
SELECT * FROM (VALUES
  (CAST(1001 AS BIGINT), 'CUST001', DATE '2024-01-15', 159.99, 'paid', '123 Main St'),
  (1002, 'CUST002', DATE '2024-01-15', 249.50, 'paid', '456 Oak Ave'),
  (1003, 'CUST003', DATE '2024-01-16', 89.99, 'paid', '789 Pine Rd'),
  (1004, 'CUST001', DATE '2024-01-16', 199.99, 'paid', '123 Main St'),
  -- Missing order 1005! (warehouse sync delay)
  (1006, 'CUST002', DATE '2024-01-17', 449.99, 'paid', '456 Oak Ave'),
  (1007, 'CUST005', DATE '2024-01-18', 99.99, 'paid', '654 Maple Dr'),
  (1008, 'CUST003', DATE '2024-01-18', 179.50, 'paid', '789 Pine Rd'),
  (1009, 'CUST006', DATE '2024-01-19', 599.99, 'paid', '987 Cedar Ln'),
  (1010, 'CUST004', DATE '2024-01-19', 139.99, 'paid', '321 Elm St')  -- Wrong amount!
) AS orders(order_id, customer_id, order_date, total_amount, payment_status, shipping_address);

-- Inventory: warehouse management system
CREATE OR REPLACE TABLE warehouse_inventory AS
SELECT * FROM (VALUES
  ('SKU-A001', 'WH-01', 150, DATE '2024-01-20'),
  ('SKU-A001', 'WH-02', 200, DATE '2024-01-20'),
  ('SKU-A002', 'WH-01', 75, DATE '2024-01-20'),
  ('SKU-A002', 'WH-02', 100, DATE '2024-01-20'),
  ('SKU-A003', 'WH-01', 50, DATE '2024-01-20'),
  ('SKU-A003', 'WH-02', 80, DATE '2024-01-20'),
  ('SKU-B001', 'WH-01', 300, DATE '2024-01-20'),
  ('SKU-B001', 'WH-02', 250, DATE '2024-01-20'),
  ('SKU-B002', 'WH-01', 125, DATE '2024-01-20'),
  ('SKU-B002', 'WH-02', 175, DATE '2024-01-20')
) AS inventory(sku, location_id, quantity, last_counted);

-- Inventory: ERP system (with discrepancies)
CREATE OR REPLACE TABLE erp_inventory AS
SELECT * FROM (VALUES
  ('SKU-A001', 'WH-01', 150, DATE '2024-01-20'),
  ('SKU-A001', 'WH-02', 200, DATE '2024-01-20'),
  ('SKU-A002', 'WH-01', 75, DATE '2024-01-20'),
  ('SKU-A002', 'WH-02', 100, DATE '2024-01-20'),
  ('SKU-A003', 'WH-01', 45, DATE '2024-01-20'),  -- Quantity discrepancy!
  ('SKU-A003', 'WH-02', 80, DATE '2024-01-20'),
  ('SKU-B001', 'WH-01', 300, DATE '2024-01-20'),
  ('SKU-B001', 'WH-02', 250, DATE '2024-01-20'),
  ('SKU-B002', 'WH-01', 125, DATE '2024-01-20')
  -- Missing SKU-B002 at WH-02!
) AS inventory(sku, location_id, quantity, last_counted);
