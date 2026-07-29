-- E-commerce revenue reconciliation: target (data warehouse)
-- Contains rounding/currency conversion differences vs source

CREATE OR REPLACE TABLE order_items AS
SELECT * FROM (VALUES
  -- Electronics / Apple -- MacBook Pro has warehouse rounding issue
  ('Electronics', 'Apple',   'iPhone 15',      999.99, 150),
  ('Electronics', 'Apple',   'MacBook Pro',   2500.00,  45),
  ('Electronics', 'Apple',   'AirPods Pro',    249.99, 300),
  -- Electronics / Samsung -- identical
  ('Electronics', 'Samsung', 'Galaxy S24',     899.99, 120),
  ('Electronics', 'Samsung', 'Galaxy Tab',     649.99,  60),
  -- Clothing / Nike -- identical
  ('Clothing',    'Nike',    'Air Max 90',     129.99, 500),
  ('Clothing',    'Nike',    'Dri-FIT Tee',     34.99, 800),
  -- Clothing / Adidas -- Ultraboost has currency conversion diff
  ('Clothing',    'Adidas',  'Ultraboost',     190.49, 350),
  ('Clothing',    'Adidas',  'Track Pants',     64.99, 600),
  -- Home & Garden / Dyson -- identical
  ('Home & Garden', 'Dyson',   'V15 Detect',   749.99,  80),
  ('Home & Garden', 'Dyson',   'Pure Cool',    549.99,  95),
  -- Home & Garden / iRobot -- identical
  ('Home & Garden', 'iRobot',  'Roomba j7+',   799.99,  70),
  ('Home & Garden', 'iRobot',  'Braava jet',   299.99, 110)
) AS t(category, brand, product, unit_price, units_sold);
