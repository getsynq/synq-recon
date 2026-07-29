-- User activity and data migration tables

-- Application event logs: raw events from the app
CREATE OR REPLACE TABLE app_event_logs AS
SELECT
  CAST(id AS BIGINT) AS event_id,
  'USER_' || CAST((id % 5) + 1 AS VARCHAR) AS user_id,
  CASE
    WHEN id % 4 = 0 THEN 'page_view'
    WHEN id % 4 = 1 THEN 'button_click'
    WHEN id % 4 = 2 THEN 'form_submit'
    ELSE 'api_call'
  END AS event_type,
  CAST('2024-01-20 10:00:00' AS TIMESTAMP) + CAST((id * 5) || ' minutes' AS INTERVAL) AS event_timestamp,
  '/page/' || CAST(id % 10 AS VARCHAR) AS page_url,
  'SESSION_' || CAST((id % 3) + 1 AS VARCHAR) AS session_id
FROM generate_series(1, 100) AS t(id);

-- Analytics database: some events dropped during ingestion
CREATE OR REPLACE TABLE analytics_events AS
SELECT
  CAST(id AS BIGINT) AS event_id,
  'USER_' || CAST((id % 5) + 1 AS VARCHAR) AS user_id,
  CASE
    WHEN id % 4 = 0 THEN 'page_view'
    WHEN id % 4 = 1 THEN 'button_click'
    WHEN id % 4 = 2 THEN 'form_submit'
    ELSE 'api_call'
  END AS event_type,
  CAST('2024-01-20 10:00:00' AS TIMESTAMP) + CAST((id * 5) || ' minutes' AS INTERVAL) AS event_timestamp,
  '/page/' || CAST(id % 10 AS VARCHAR) AS page_url,
  'SESSION_' || CAST((id % 3) + 1 AS VARCHAR) AS session_id
FROM generate_series(1, 100) AS t(id)
WHERE id NOT IN (25, 50, 75);  -- 3 events dropped during ingestion

-- Data migration: legacy system
CREATE OR REPLACE TABLE legacy_customers AS
SELECT * FROM (VALUES
  (CAST(10001 AS BIGINT), 'John', 'Smith', 'john.smith@example.com', '555-0101', DATE '2020-03-15', 1250.50, 1500, true),
  (10002, 'Jane', 'Doe', 'jane.doe@example.com', '555-0102', DATE '2020-04-22', 2350.75, 2800, true),
  (10003, 'Bob', 'Johnson', 'bob.j@example.com', '555-0103', DATE '2020-05-10', 890.00, 950, true),
  (10004, 'Alice', 'Williams', 'alice.w@example.com', '555-0104', DATE '2020-06-18', 3500.25, 4200, true),
  (10005, 'Charlie', 'Brown', 'charlie.b@example.com', '555-0105', DATE '2020-07-25', 450.00, 500, false),
  (10006, 'Diana', 'Miller', 'diana.m@example.com', '555-0106', DATE '2020-08-30', 5600.00, 6800, true),
  (10007, 'Eve', 'Davis', 'eve.d@example.com', '555-0107', DATE '2020-09-12', 1200.00, 1450, true),
  (10008, 'Frank', 'Wilson', 'frank.w@example.com', '555-0108', DATE '2020-10-05', 2100.50, 2500, true),
  (10009, 'Grace', 'Moore', 'grace.m@example.com', '555-0109', DATE '2020-11-20', 780.25, 890, true),
  (10010, 'Henry', 'Taylor', 'henry.t@example.com', '555-0110', DATE '2020-12-14', 4200.00, 5100, true)
) AS customers(customer_id, first_name, last_name, email, phone, created_date, account_balance, loyalty_points, is_active);

-- Data migration: new system (with migration errors)
CREATE OR REPLACE TABLE new_system_customers AS
SELECT * FROM (VALUES
  (CAST(10001 AS BIGINT), 'John', 'Smith', 'john.smith@example.com', '555-0101', DATE '2020-03-15', 1250.50, 1500, true),
  (10002, 'Jane', 'Doe', 'jane.doe@example.com', '555-0102', DATE '2020-04-22', 2350.75, 2800, true),
  (10003, 'Bob', 'Johnson', 'bob.j@example.com', '555-0103', DATE '2020-05-10', 890.00, 950, true),
  (10004, 'Alice', 'Williams', 'alice.w@example.com', '555-0104', DATE '2020-06-18', 3500.25, 4200, true),
  (10005, 'Charlie', 'Brown', 'charlie.brown@example.com', '555-0105', DATE '2020-07-25', 450.00, 500, false),  -- Email typo!
  (10006, 'Diana', 'Miller', 'diana.m@example.com', '555-0106', DATE '2020-08-30', 5600.00, 6800, true),
  (10007, 'Eve', 'Davis', 'eve.d@example.com', '555-0107', DATE '2020-09-12', 1200.00, 1450, true),
  (10008, 'Frank', 'Wilson', 'frank.w@example.com', '555-0108', DATE '2020-10-05', 2100.50, 2500, true),
  (10009, 'Grace', 'Moore', 'grace.m@example.com', '555-0109', DATE '2020-11-20', 780.25, 890, true)
  -- Missing customer 10010!
) AS customers(customer_id, first_name, last_name, email, phone, created_date, account_balance, loyalty_points, is_active);
