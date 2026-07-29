# synq-recon Examples

This directory contains user-friendly business scenario examples using in-memory DuckDB databases. For algorithm/config tests, see the `tests/` directory.

## Available Examples

| File | Description |
|------|-------------|
| `ecommerce.yaml` | Payment gateway vs warehouse orders, inventory vs ERP |
| `ecommerce-aggregate.yaml` | Hierarchical revenue drill-down (category → brand → product) |
| `financial.yaml` | Core banking vs data warehouse transactions |
| `user-activity.yaml` | App logs vs analytics DB, legacy data migration |
| `etl-pipeline.yaml` | Operational vs reporting daily sales (aggregate mode) |
| `time-travel.yaml` | Snowflake time-travel snapshot comparison (needs real DWH) |
| `config.yaml` | Production template with PostgreSQL/Snowflake examples |

## Quick Start

```bash
# Build (CGO on, so the DuckDB fixtures work)
go build -o synq-recon ./cmd/synq-recon

# Check the configuration (offline)
synq-recon check-config examples/ecommerce.yaml

# Run quick check
synq-recon run-check examples/ecommerce.yaml

# Locate the differences a quick check found
synq-recon run-drill examples/ecommerce.yaml --include ecommerce-orders

# Or do both in one pass
synq-recon run examples/ecommerce.yaml --auto-drill

# Run all examples and tests
./examples/test-all-examples.sh
```

`ecommerce.yaml` is walked through end to end, with expected output, in
[the operating guide](../AGENTS.md) § Worked example.

These examples run against in-memory DuckDB and every one of them is expected to
find mismatches — that is what they demonstrate — so exit code 1 is the correct
outcome, not a failure. Each reconciliation's `description` states what it should
find.

Add `--no-report` if you have a stored credential and want the run to stay off
the network entirely.

## Key Concepts

### Two-Stage Reconciliation

**Stage 1: Quick Check**
- Single query per database
- Compares total row count and checksum sum
- O(1) complexity - instant for any table size

**Stage 2: Bisection Drill-Down**
- Recursively splits key ranges
- Locates specific mismatches with O(log n) queries
- Bucketed queries optimize database round-trips

### Setup & Teardown

Examples use `setup` blocks to create tables and `teardown` blocks to clean up:

```yaml
setup:
  my-db:
    - CREATE TABLE orders AS SELECT ...

teardown:
  my-db:
    - DROP TABLE IF EXISTS orders
```

Test files can share SQL fixtures via `setup_file`:

```yaml
setup_file:
  my-db: fixtures/shared-tables.sql
```

### Privacy Considerations

By default, synq-recon is privacy-preserving:
- Only checksums and counts leave the database
- No actual data values are retrieved
- Use `reporting.level: detailed` only when you have proper consent

## Connection Types

These examples use in-memory DuckDB. synq-recon supports:
PostgreSQL, MySQL, Snowflake, BigQuery, ClickHouse, Databricks, Redshift, Trino,
MSSQL, Oracle, Athena, Fabric, DuckDB.

See `config.yaml` for connection configuration examples, and the repository
README for the full table with per-platform notes.

## Further Reading

- `INDEX.md` — Complete directory index and navigation
- [the operating guide](../AGENTS.md) — driving the CLI: commands, flags, output, exit codes, cost
- `../README.md` — What the tool is, and the configuration reference
- `../CLAUDE.md` — Architecture, for changing `synq-recon` itself
