# synq-recon Examples & Tests

## Directory Structure

```
examples/                        # User-friendly business scenarios
  ecommerce.yaml                 # E-commerce order + inventory reconciliation
  ecommerce-aggregate.yaml       # Hierarchical revenue drill-down (category/brand/product)
  financial.yaml                 # Financial transaction matching
  user-activity.yaml             # User activity logs + data migration
  etl-pipeline.yaml              # ETL pipeline validation (aggregate mode)
  time-travel.yaml               # Snapshot comparison (requires real DWH)
  config.yaml                    # Production-ready template with connection examples
  fixtures/                      # SQL setup files for examples
    ecommerce.sql                # Payment gateway, warehouse, inventory tables
    ecommerce-aggregate-source.sql  # Revenue source (operational DB)
    ecommerce-aggregate-target.sql  # Revenue target (data warehouse, with diffs)
    etl-pipeline.sql             # Operational and reporting sales tables
    financial.sql                # Core banking and warehouse transactions
    user-activity.sql            # Event logs, legacy/new customer tables
    config-source.sql            # Tables for the config.yaml template
    config-target.sql

tests/                           # Algorithm/config/feature tests
  basic-check.yaml               # Identical, missing, modified rows
  reconciliation-modes.yaml      # row_count vs full modes
  aggregate-mode.yaml            # Aggregate functions and thresholds
  aggregate-hierarchical.yaml    # Cumulative GROUP BY drill-down
  hash-algorithms.yaml           # MD5, auto selection, NULL handling
  complex-types.yaml             # Timestamps, decimals, NULLs, booleans
  column-mapping.yaml            # Case-insensitive, explicit mappings
  cutoff-filter.yaml             # Dynamic cutoff watermarks
  hash-segmentation.yaml         # Hash bucketing strategy
  time-segmentation.yaml         # Time-bucketed segmentation
  segmentation-factors.yaml      # Different bisection factors/thresholds
  query-templating.yaml          # Template variable interpolation
  table-mode.yaml                # table: datasets, column selection
  where-filter.yaml              # Dataset where: filters
  reporting-levels.yaml          # count_only, with_keys, detailed
  fixtures/
    shared-tables.sql            # Shared setup SQL for test files
    hash-segmentation.sql
    query-templating.sql
    where-filter.sql
```

## Quick Start

```bash
# Build
go build -o synq-recon ./cmd/synq-recon

# Check a config (offline)
./synq-recon check-config tests/basic-check.yaml

# Run quick check
./synq-recon run-check examples/ecommerce.yaml

# Run with auto drill-down
./synq-recon run examples/ecommerce.yaml --auto-drill

# Run all tests
./examples/test-all-examples.sh
```

The full command surface is in [`../AGENTS.md`](../AGENTS.md).

## Examples (Business Scenarios)

| File | Description |
|------|-------------|
| `ecommerce.yaml` | Payment gateway vs warehouse orders, inventory vs ERP |
| `ecommerce-aggregate.yaml` | Hierarchical revenue drill-down (category -> brand -> product) |
| `financial.yaml` | Core banking vs data warehouse transactions |
| `user-activity.yaml` | App logs vs analytics DB, legacy data migration |
| `etl-pipeline.yaml` | Operational vs reporting daily sales (aggregate mode) |
| `time-travel.yaml` | Snowflake time-travel snapshot comparison (needs real DWH) |
| `config.yaml` | Production template with PostgreSQL/Snowflake examples |

## Tests (Feature/Algorithm Checks)

| File | Focus |
|------|-------|
| `basic-check.yaml` | Core reconciliation: match, mismatch, count, edge cases |
| `reconciliation-modes.yaml` | `row_count` vs `full` mode, bisection on/off |
| `aggregate-mode.yaml` | SUM, COUNT, AVG, MIN, MAX with thresholds |
| `aggregate-hierarchical.yaml` | Cumulative `GROUP BY` drill-down through `group_columns` |
| `hash-algorithms.yaml` | MD5, auto-select, NULL handling, checksums |
| `complex-types.yaml` | TIMESTAMP, DATE, BOOLEAN, BIGINT, special chars |
| `column-mapping.yaml` | Object/array formats, partial mapping, cross-schema |
| `cutoff-filter.yaml` | Watermark derivation, combine/truncate/offset, custom apply |
| `hash-segmentation.yaml` | Hash strategy vs quantile baseline |
| `time-segmentation.yaml` | `strategy: time` with `time_column` / `time_granularity` |
| `segmentation-factors.yaml` | Factor 4/64, threshold high/low |
| `query-templating.yaml` | `{{ variable }}` interpolation and `--var` overrides |
| `table-mode.yaml` | `table:` datasets, `columns` / `exclude_columns` |
| `where-filter.yaml` | Dataset `where:` filters |
| `reporting-levels.yaml` | count_only, with_keys, detailed, sample_limit |

## Features

Both examples and tests use `setup_file` to load SQL from external fixture files,
keeping YAML configs focused on reconciliation logic rather than table definitions.

All DuckDB-based files work without external dependencies. The `time-travel.yaml` example
requires a real Snowflake/BigQuery/Databricks connection with time-travel support.
