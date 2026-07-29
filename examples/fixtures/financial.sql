-- Financial transaction reconciliation: core banking vs data warehouse

-- Core banking system: authoritative transaction record
CREATE OR REPLACE TABLE bank_transactions AS
SELECT * FROM (VALUES
  (CAST(50001 AS BIGINT), 'ACC-10001', TIMESTAMP '2024-01-20 09:15:23', CAST(1250.00 AS DECIMAL(18,2)), 'DEBIT', 'USD', 'posted'),
  (50002, 'ACC-10002', TIMESTAMP '2024-01-20 10:22:17', 5000.00, 'CREDIT', 'USD', 'posted'),
  (50003, 'ACC-10001', TIMESTAMP '2024-01-20 11:45:33', 75.50, 'DEBIT', 'USD', 'posted'),
  (50004, 'ACC-10003', TIMESTAMP '2024-01-20 14:30:45', 10000.00, 'CREDIT', 'USD', 'posted'),
  (50005, 'ACC-10002', TIMESTAMP '2024-01-20 15:18:56', 2500.00, 'DEBIT', 'USD', 'posted'),
  (50006, 'ACC-10004', TIMESTAMP '2024-01-20 16:25:12', 150.00, 'DEBIT', 'USD', 'posted'),
  (50007, 'ACC-10001', TIMESTAMP '2024-01-21 08:12:34', 3000.00, 'CREDIT', 'USD', 'posted'),
  (50008, 'ACC-10003', TIMESTAMP '2024-01-21 09:45:21', 500.00, 'DEBIT', 'USD', 'posted'),
  (50009, 'ACC-10002', TIMESTAMP '2024-01-21 11:30:15', 7500.00, 'CREDIT', 'USD', 'posted'),
  (50010, 'ACC-10005', TIMESTAMP '2024-01-21 13:55:47', 1200.00, 'DEBIT', 'USD', 'posted')
) AS txn(transaction_id, account_number, transaction_date, amount, transaction_type, currency, status);

-- Data warehouse: ETL'd data (may have delays or transform errors)
CREATE OR REPLACE TABLE warehouse_transactions AS
SELECT * FROM (VALUES
  (CAST(50001 AS BIGINT), 'ACC-10001', TIMESTAMP '2024-01-20 09:15:23', CAST(1250.00 AS DECIMAL(18,2)), 'DEBIT', 'USD', 'posted'),
  (50002, 'ACC-10002', TIMESTAMP '2024-01-20 10:22:17', 5000.00, 'CREDIT', 'USD', 'posted'),
  (50003, 'ACC-10001', TIMESTAMP '2024-01-20 11:45:33', 75.50, 'DEBIT', 'USD', 'posted'),
  (50004, 'ACC-10003', TIMESTAMP '2024-01-20 14:30:45', 10000.00, 'CREDIT', 'USD', 'posted'),
  (50005, 'ACC-10002', TIMESTAMP '2024-01-20 15:18:56', 2500.00, 'DEBIT', 'USD', 'posted'),
  (50006, 'ACC-10004', TIMESTAMP '2024-01-20 16:25:12', 150.00, 'DEBIT', 'USD', 'posted'),
  (50007, 'ACC-10001', TIMESTAMP '2024-01-21 08:12:34', 3000.00, 'CREDIT', 'USD', 'posted'),
  (50008, 'ACC-10003', TIMESTAMP '2024-01-21 09:45:21', 5000.00, 'DEBIT', 'USD', 'posted')  -- Wrong amount! ($500 -> $5000)
  -- Missing transaction 50009!
  -- Missing transaction 50010!
) AS txn(transaction_id, account_number, transaction_date, amount, transaction_type, currency, status);
