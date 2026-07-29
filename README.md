# synq-recon

Coalesce Quality database reconciliation tool, using a hierarchical checksum bisection algorithm.

## What It Does

`synq-recon` efficiently detects data differences between source and target databases without transferring actual data. It uses a two-stage approach:

1. **Quick Check**: Compare row counts and checksums to detect if any differences exist (single query per database)
2. **Bisection Drill-Down**: Recursively bisect the key space to locate specific mismatches with O(log n) complexity

**Privacy-first**: By default, only checksums and counts leave the database - no actual data values are retrieved.

## Installation

### Binaries

Pick a version from the [releases page](https://github.com/getsynq/synq-recon/releases)
— the archive filename carries it, so it has to be named explicitly:

```bash
VERSION=0.2.0
OS=$(uname -s | tr '[:upper:]' '[:lower:]')          # darwin or linux
ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

curl -fL "https://github.com/getsynq/synq-recon/releases/download/v${VERSION}/synq-recon_${VERSION}_${OS}_${ARCH}.tar.gz" \
  | tar -xz
sudo mv synq-recon /usr/local/bin/
```

Builds are published for macOS and Linux on both amd64 and arm64. Each archive
also carries this README, `AGENTS.md` and the `examples/` suites, and every release
ships a `checksums.txt` (`sha256sum -c checksums.txt --ignore-missing`).

Every published binary is built with CGO enabled, so `type: duckdb` works — which
is what makes the examples runnable with no warehouse to stand up. On macOS a
downloaded binary may be quarantined; `xattr -d com.apple.quarantine
/usr/local/bin/synq-recon` clears the flag.

### Docker

```bash
docker pull europe-docker.pkg.dev/synq-cicd-public/synq-public/synq-recon:latest
docker run --rm -v "$PWD:/work" -w /work \
  europe-docker.pkg.dev/synq-cicd-public/synq-public/synq-recon:latest \
  check-config suite.yaml
```

The image is built with CGO enabled, so `type: duckdb` works inside it — which is what makes every example in `examples/` runnable from the image with no warehouse to stand up. If a DuckDB connection fails with a driver error, the image predates that: pull `:latest`.

### From Source

`synq-recon` lives in the `getsynq/cloud` monorepo, which is private, so this path is for anyone with access to it:

```bash
cd synq-recon
go build -o synq-recon ./cmd/synq-recon
```

CGO must be enabled (it is by default) for DuckDB connections.

## Using the CLI

**[The operating guide](AGENTS.md)** — shipped beside the binary as `AGENTS.md` —
covers the command loop, the full
command and flag reference, how to read the output, exit codes, what each command
costs, and a worked example runnable against the DuckDB fixtures in this
repository. It is written for a coding agent driving the tool, and it is the
single place CLI usage is documented; this README covers what the tool *is* and
how a suite is *configured*.

The shortest path from nothing to a located difference:

```bash
synq-recon check-config suite.yaml          # validate offline
synq-recon check-config suite.yaml --db     # validate against the databases
synq-recon run-check    suite.yaml          # compare counts and checksums
synq-recon run          suite.yaml --auto-drill   # locate what differs
```

Exit code 1 from a run means differences were found — a result, not a failure.

Beyond local execution, the CLI manages the full lifecycle in a Coalesce Quality
workspace: `upload-config` saves a suite, `run-remote` executes it on the backend
against workspace integrations, `promote` publishes it as a scheduled or
API-triggerable deployment, and `recheck` / `drill-deeper` replay a finished run.
`auth login` authenticates; run `auth whoami` to confirm which workspace you are
acting on before anything that writes. Credential resolution order, scopes and
the multi-region store are covered in [the operating guide](AGENTS.md) § Confirm the
target. The credential store is shared with the other Coalesce Quality CLIs, so one
login covers all of them.

## Supported Databases

| Database   | Status    | Notes |
|------------|-----------|-------|
| PostgreSQL | Supported | |
| Snowflake  | Supported | Key pair auth supported |
| BigQuery   | Supported | |
| MySQL      | Supported | |
| Redshift   | Supported | |
| Databricks | Supported | |
| ClickHouse | Supported | |
| DuckDB     | Supported | Local files and MotherDuck cloud; local files need a CGO-enabled build |
| Trino      | Supported | |
| MSSQL      | Supported | SQL Server |
| Oracle     | Supported | |
| Athena     | Supported | |
| Fabric     | Supported | Microsoft Fabric warehouse |

## Configuration Reference

The field-level source of truth is the published schema, at a stable versioned URL: the [configuration reference](https://schemas.synq.io/synq-recon/v1/config.html) for every field, type, constraint and default, and [`config.schema.json`](https://schemas.synq.io/synq-recon/v1/config.schema.json) to validate against or point an editor at. It is generated from `schemas/config.schema.json` in this module. This section covers the shape and the parts that need explaining.

A suite's top level:

```yaml
name: orders-consistency          # short machine identifier
title: "Orders consistency"
description: "Payment gateway vs warehouse"

connections: {...}                # see Connection Types
reconciliations: {...}            # see Reconciliation Settings
variables: {...}                  # see Template Variables
annotations: {...}                # see Annotations
setup: {...}                      # see Setup and Teardown
teardown: {...}
setup_file: {...}
teardown_file: {...}
teardown_on_failure: false        # run teardown even when reconciliations fail
ignore_setup_errors: false        # log setup errors as warnings and continue
strict_time_references: false     # turn NOW()/CURRENT_DATE warnings into an error
synq: {...}                       # see Reporting Credentials
```

### Connection Types

Every connection accepts two settings alongside its database block:

```yaml
connections:
  my-postgres:
    disabled: false      # skip this connection during execution
    parallelism: 8       # max parallel queries on this connection (1-256, default 8)
    postgres: {...}
```

`parallelism` bounds concurrency at the connection, which matters when `--concurrency` fans several reconciliations onto the same warehouse. `disabled: true` keeps a connection defined but out of the run — useful for parking one side of a suite without deleting its wiring.

#### PostgreSQL

```yaml
connections:
  my-postgres:
    postgres:
      host: localhost
      port: 5432
      database: mydb
      username: myuser
      password: ${POSTGRES_PASSWORD}
      allow_insecure: false  # optional, default false
```

#### Snowflake

```yaml
connections:
  my-snowflake:
    snowflake:
      account: myorg.us-east-1
      warehouse: COMPUTE_WH
      role: ANALYST
      username: myuser
      password: ${SNOWFLAKE_PASSWORD}
      databases:
        - MYDB
      # Optional: key pair authentication
      private_key_file: /path/to/key.pem
      private_key_passphrase: ${KEY_PASSPHRASE}
```

#### DuckDB (Local and MotherDuck)

```yaml
connections:
  # Local file-based DuckDB
  my-local-duckdb:
    duckdb:
      database: /path/to/file.duckdb  # or ":memory:"

  # MotherDuck cloud-hosted DuckDB
  my-motherduck:
    duckdb:
      database: my_account  # MotherDuck account name
      motherduck_token: ${MOTHERDUCK_TOKEN}
```

### Reconciliation Settings

```yaml
reconciliations:
  my-recon:
    title: "Human-readable title"
    description: "Optional description"

    source:
      connection: source-conn
      query: |
        SELECT id, name, value FROM source_table
        WHERE created_at >= '2024-01-01'
      # Alternative: specify a table directly (mutually exclusive with query)
      # table: schema.source_table
      # columns: [id, name, value]        # optional: restrict columns
      # exclude_columns: [internal_col]   # optional: exclude columns
      # where: "region = 'EU'"            # optional: filter, table datasets only
      # as_of: "2026-02-01 00:00:00"      # optional: time-travel timestamp

    target:
      connection: target-conn
      query: |
        SELECT id, name, value FROM target_table
        WHERE created_at >= '2024-01-01'

    # Primary key column for segmentation
    key_column: id
    # Composite key: use key_columns (or key_column) with a list. Bisection
    # orders and range-filters on the column tuple so a matching primary
    # key / index can still prune. Both keys accept a string or a list.
    # key_columns: [workspace, path]

    # Comparison mode
    mode: row_checksum  # Options: row_count, row_checksum (default), aggregate
                        # `full` is accepted as a legacy spelling of row_checksum

    # Column mapping (optional)
    # Automatically handles case differences (user_id → USER_ID)
    # Explicit mappings for different column names:
    column_mapping:
      source_col: target_col
      invoice_amount: customer_daily_sum
    # Disable automatic case-insensitive matching:
    case_insensitive: false  # default: true

    # Hash algorithm (optional)
    hash_algorithm: auto  # Options: auto, md5, farm_fingerprint, xxhash64
                          # auto selects best common algorithm across databases

    # Bisection settings (for drill-down)
    bisection:
      enabled: true
      factor: 32        # Segments per bisection level (default: 32)
      threshold: 16384  # Stop drilling below this row count (default: 16384)
      strategy: auto    # Segmentation strategy: auto, quantile, hash, time

    # Time window for incremental comparison (optional)
    window:
      column: created_at        # Column being windowed (metadata)
      lookback: "14d"           # Duration: "14d", "2h", "1w"
      strategy: sliding         # "sliding" (default) or "fixed"

    # Dynamic cutoff: exclude rows not yet synced (optional) — see Cutoff below
    cutoff:
      column: created_at
      truncate: HOUR
      offset: "-30m"

    # How much detail a mismatch may reveal (optional) — see Privacy Levels
    reporting:
      level: count_only         # count_only (default), with_keys, detailed
      sample_limit: 100         # max sample rows at with_keys / detailed
      consent_acknowledged: false  # required for `detailed`

    # Annotations attached to this reconciliation (optional) — see Annotations
    annotations:
      team: data-platform

    # Per-reconciliation setup/teardown (optional) — see Setup and Teardown
    setup: {...}
    teardown: {...}
    setup_file: {...}
    teardown_file: {...}
    teardown_on_failure: true    # inherits from suite level when unset
    ignore_setup_errors: false   # inherits from suite level when unset

    # Error handling (optional)
    error_handling:
      query_timeout: "30s"         # Per-query timeout (default: uses global --timeout)
      max_retries: 2               # Retry attempts (default: 2)
      retry_initial_delay: "1s"    # Initial backoff delay (default: "1s")
      retry_backoff_factor: 2.0    # Backoff multiplier (default: 2.0)
```

`where` is a filter on a `table:` dataset, applied as `WHERE (condition)` and supporting `{{ variable }}` interpolation. It is how you narrow a table without switching to `query:` and losing the column resolution `table:` gives you. It is not accepted alongside `query:` — put the predicate in the query instead.

### Aggregate Mode

Compares aggregated metrics grouped by one or more columns with hierarchical drill-down.
Useful for validating ETL pipelines, aggregation jobs, and summary tables.

```yaml
reconciliations:
  revenue-by-product:
    mode: aggregate
    key_column: category
    aggregate:
      # Measures to compare (supports plural function syntax)
      measures:
        - column: revenue
          function: [SUM, AVG]    # Expands to SUM(revenue) and AVG(revenue)
        - column: units_sold
          function: SUM

      # Hierarchical drill-down columns (optional)
      # Falls back to [key_column] if not set
      group_columns: [category, brand, product]

      # Thresholds for acceptable differences (optional)
      thresholds:
        absolute: 0.01            # Max absolute difference
        percentage: 0.001         # Max percentage difference (0.1%)
        percentage_mode: source   # source (default), target, or symmetric

        # Per group_column overrides (column-level thresholds)
        per_column:
          product:
            absolute: 1.0
            # Per-measure overrides nested within per_column
            per_measure:
              "SUM(revenue)":
                absolute: 10.0

        # Per-measure overrides (global, keyed by "FUNC(column)")
        per_measure:
          "AVG(revenue)":
            percentage: 0.05
```

**Threshold resolution** (most specific wins):
1. `per_column[col].per_measure["FUNC(col)"]`
2. `per_measure["FUNC(col)"]`
3. `per_column[col]`
4. Global `thresholds`

### Setup and Teardown

Run SQL queries before and after reconciliations:

```yaml
# Suite-level: runs once before/after all reconciliations
setup:
  source-db:
    - CREATE TEMP TABLE staging AS SELECT * FROM raw_data
teardown:
  source-db:
    - DROP TABLE IF EXISTS staging
teardown_on_failure: true  # Run teardown even on failure (default: false)
ignore_setup_errors: false # Log setup errors as warnings and keep going (default: false)

# Or load SQL from files
setup_file:
  source-db: fixtures/setup-source.sql
  target-db: fixtures/setup-target.sql
teardown_file:
  source-db: fixtures/teardown-source.sql

reconciliations:
  my-recon:
    # Per-reconciliation setup/teardown (runs before/after each recon).
    # Every suite-level key is available here too, including setup_file,
    # teardown_file, teardown_on_failure and ignore_setup_errors — the last
    # two inherit the suite's value when omitted.
    setup:
      source-db:
        - INSERT INTO staging SELECT ...
    teardown:
      source-db:
        - DELETE FROM staging WHERE ...
```

`setup_file` / `teardown_file` take a path per connection and run the file's statements as if they had been written inline, which is how the suites in `examples/` and `tests/` share fixtures. `ignore_setup_errors: true` downgrades a failing setup statement to a warning and runs the comparison anyway — right for idempotent bootstrap SQL (`CREATE TABLE IF NOT EXISTS`), wrong when the setup is what produces the data being compared.

### Cutoff

A cutoff is the defence against false mismatches when the target lags the source. It derives a **watermark** from the actual data, then filters both sides to at-or-below it, so rows still in flight are excluded from the comparison instead of being reported as missing.

The simplest form names one column on both sides:

```yaml
reconciliations:
  orders-sync:
    source: { connection: pg, table: public.orders }
    target: { connection: ch, table: warehouse.orders }
    key_column: id
    mode: full
    cutoff:
      column: created_at
```

Progressive disclosure, in three levels:

```yaml
# Level 2 — a different watermark column per side
cutoff:
  source_column: created_at
  target_column: synced_at

# Level 3 — full control per side
cutoff:
  source:
    column: created_at
    aggregate: MAX          # MAX (default) or MIN
  target:
    column: synced_at
    query: |                # or derive it yourself; must return one row,
      SELECT MAX(synced_at) AS watermark FROM warehouse.orders
  combine: min              # min (default), max, source, target
  truncate: HOUR            # HOUR, DAY, WEEK, MONTH, QUARTER, YEAR
  offset: "-30m"            # applied after truncation; negative = safety buffer
  apply:                    # filter a different column than the one derived from
    source: { column: created_at, operator: "<=" }
    target: { column: created_at, operator: "<=" }
```

Resolution order: derive each configured side's watermark → combine them → truncate → apply the offset → build the `WHERE` clause per side.

`combine: min` is the default and the safe choice: the lower of the two watermarks is the point both sides have certainly reached. `max`, `source` and `target` all risk keeping rows one side has and the other does not, which is a mismatch you created. `truncate` plus a negative `offset` buys a margin for a pipeline that writes slightly out of order.

The watermark need not be a timestamp — a monotonic sequence works, in which case `truncate` and `offset` are skipped rather than applied. The derived watermarks, the combined cutoff value and both `WHERE` clauses are all recorded in the audit log, so a run's comparison window is always recoverable.

### Annotations

Annotations are name/value labels on a suite or a single reconciliation. Reconciliation-level annotations are merged with the suite's, and they follow a promoted suite into the platform, where they annotate the resulting assets and checks.

Three accepted shapes, all equivalent:

```yaml
# Map shorthand — one value, several values, or a bare name
annotations:
  team: data-platform
  domain: [revenue, billing]
  critical:

# Canonical list form
annotations:
  - name: team
    values: [data-platform]
  - name: domain
    values: [revenue, billing]
  - name: critical
```

Whichever you write, the loader normalises to the canonical list — names and values sorted — so `suite yaml` output and version-history diffs never show order-only changes. A name is required; values are optional. Both names and values cap at 50 characters, with at most 20 values per name.

### Environments

An environment is a named set of overrides applied at load time — most usefully swapping the database or schema a suite points at while you author against a dev copy:

```yaml
# environments.yaml, or <suite>.env.yaml next to the suite
environments:
  dev:
    description: "Author against the dev copy"
    connections:
      snowflake-main:
        table_path:
          database: DEV_SANDBOX
          schema: ANALYTICS
          table_prefix: ""
          table_suffix: "_v2"
    datasets:
      orders-daily.source:
        table_path:
          schema: STAGING
    variables:
      lookback_days: "7"
```

```bash
synq-recon run-check suite.yaml --environment dev
synq-recon run-check suite.yaml -e dev --env-file path/to/environments.yaml
```

With `--env-file` omitted, the file is discovered as `<suite>.yaml.env.yaml`, `<suite>.env.yaml`, or `environments.yaml` in the suite's directory, in that order.

An override resolves most-specific-first: a `datasets` entry keyed `<reconciliation>.source` or `<reconciliation>.target` beats a `connections` entry, and only the fields it sets are changed. `table_path` overrides rewrite a `table:` reference, so a dataset written as `query:` is unaffected — `variables` are the lever there.

**Environments are local-only.** `--environment` and `--env-file` are applied by this CLI when it loads a suite; the workspace does not apply them, so a suite uploaded with `upload-config` and run with `run-remote` or a promoted deployment sees no overrides. Use them for local authoring, not to model dev and prod in the platform.

### Reporting Credentials

The `synq:` block holds the credentials and endpoints used to report a run's audit log. Every field is also settable by flag or environment variable, and flags win over YAML, which wins over the environment:

```yaml
synq:
  client_id: ${RECON_CLIENT_ID}
  client_secret: ${RECON_CLIENT_SECRET}
  endpoint: developer.synq.io:443                    # gRPC endpoint for the API
  oauth_url: https://developer.synq.io/oauth2/token  # derived from endpoint when unset
```

| YAML | Flag | Environment | Notes |
|---|---|---|---|
| `client_id` | `--client-id` | `QUALITY_CLIENT_ID` | |
| `client_secret` | `--client-secret` | `QUALITY_CLIENT_SECRET` | |
| `endpoint` | `--endpoint` | `QUALITY_API_ENDPOINT` | Also selects which region's stored credential is used. `--region eu\|us\|au` names a deployment instead |
| `oauth_url` | — | — | Token URL for the client-credentials grant. Derived from `endpoint` when unset; set it only for a deployment whose token endpoint sits elsewhere. Does not affect the browser login, which discovers its auth server from the host |
| `ingest_endpoint` | — | — | Accepted by the schema — the block is a shared type — but **`synq-recon` ignores it**. Audit logs always go to `endpoint` |

Do not commit a literal secret — use `${VAR}` as above, or leave the block out entirely and rely on the environment. A suite carrying credentials is also a suite you cannot safely `upload-config`.

`QUALITY_TOKEN` has no YAML equivalent by design; it is a pre-issued token for CI, not suite configuration.

The `--synq-client-id` / `--synq-client-secret` / `--synq-endpoint` flags and the
`SYNQ_`-prefixed variables are the previous spellings. They still work — nothing
in an existing pipeline has to change — but the names above are the ones every
Coalesce Quality CLI now shares.

### Environment Variables

Use `${VAR_NAME}` syntax for sensitive values:

```yaml
password: ${POSTGRES_PASSWORD}
password: ${DB_PASS:-default_value}  # with default
```

## Reconciliation Modes

### Row Count Mode (`mode: row_count`)

Compares only row counts - fastest, detects missing/extra rows but not modified values.

### Row Checksum Mode (`mode: row_checksum`, default)

Compares row counts and checksums of all columns - detects any differences including modified values. `full` is accepted as a legacy spelling; the YAML writer emits `row_checksum`.

### Aggregate Mode (`mode: aggregate`)

Compares aggregated metrics (SUM, COUNT, AVG, MIN, MAX) with hierarchical drill-down through `group_columns`. Only mismatched groups are drilled deeper, making it efficient for large datasets. See [Aggregate Mode](#aggregate-mode) above.

## Column Mapping

Handle different column names between source and target databases:

**Automatic case-insensitive matching** (default):
```yaml
# Automatically matches: user_id ↔ USER_ID, email ↔ Email
case_insensitive: true  # default
```

**Explicit column mapping**:
```yaml
# Object format
column_mapping:
  source_col: target_col
  invoice_amount: total_payment

# Array format
column_mapping:
  - source: order_id
    target: transaction_number
  - source: amount
    target: payment_total
```

Explicit mappings override automatic case matching.

## Composite Keys

Tables with a multi-column natural key (e.g. `(workspace, path)`) can declare all
key columns at once. Both `key_column` and `key_columns` accept either a single
string or a list:

```yaml
reconciliations:
  assets:
    source: { connection: pg, table: public.assets }
    target: { connection: ch, table: schema.latest_assets }
    key_columns: [workspace, path]   # or: key_column: [workspace, path]
    mode: full
```

Bisection orders and range-filters on the **tuple** of real columns (a
lexicographic, dialect-portable expansion), so a matching primary key / index on
`(workspace, path)` can still prune each segment — no full-table scan and no need
to synthesise a concatenated key. A single column is written back as the scalar
`key_column`; multiple columns as a `key_columns` list.

## Template Variables

Use `{{ }}` syntax in queries for time-consistent reconciliation:

```yaml
variables:
  start_date: "{{ today - 7d }}"
  end_date: "{{ today }}"

reconciliations:
  orders:
    source:
      query: |
        SELECT * FROM orders
        WHERE created_at >= '{{ start_date }}' AND created_at < '{{ end_date }}'
```

Built-in expressions:

| Expression | Resolves to |
|---|---|
| `{{ today }}` / `{{ yesterday }}` | a date, `YYYY-MM-DD` |
| `{{ now }}` | the run's reference instant, RFC 3339 |
| `{{ now(2006-01-02 15:04) }}` | `now`, in a Go time layout |
| `{{ today - 7d }}` / `{{ now - 2h }}` | a base minus an offset, in `d`, `h`, `m` (minutes) or `w` |

Only subtraction is supported, and the base must be `now`, `today` or `yesterday` — there is no filter syntax.

Override from CLI: `--var start_date=2026-01-01`

**Time reference warnings**: `check-config` warns if queries use SQL functions like `NOW()`, `CURRENT_DATE`, or `GETDATE()` directly — these execute at slightly different times on source and target, causing false mismatches. Use template variables instead. Enable `strict_time_references: true` to make these warnings into errors.

## How It Works

### Hash Algorithm Negotiation

Automatically selects the best hash algorithm supported by both databases:
- **farm_fingerprint** - Fastest, for BigQuery cross-DB reconciliations
- **md5** - Universal fallback, supported by all databases
- **xxhash64** - Fast, for same-database reconciliations (Databricks only)

Override with `hash_algorithm: md5` in config if needed.

### Checksum Algorithm

Each row's checksum is computed as:
```
row_checksum = TRUNCATE_48_BITS(MD5(col1 || '|' || col2 || ...)) - 2^47
```

The offset centering (`- 2^47`) prevents integer overflow when summing millions of checksums.

Segment checksum is simply:
```
segment_checksum = SUM(row_checksum)
```

### Bisection Algorithm

1. Compare total count and checksum for entire dataset
2. If they match → data is identical, done
3. If they differ → split key range into N segments (default: 32)
4. Compare each segment's count and checksum
5. Recursively drill into mismatching segments
6. Stop when segment size falls below threshold

This achieves **O(log n)** query complexity for locating single-row differences in mostly-identical tables.

### Segmentation Strategies

| Strategy | How It Works | Key Exposure | Drill-Down |
|----------|-------------|--------------|------------|
| `quantile` (default) | NTILE-based key-range splitting | Exposes key boundaries | Recursive multi-level |
| `hash` | `MOD(hash(key), N)` bucket assignment | No key exposure at top level | Hybrid: hash first level, then quantile within buckets |
| `time` | Time-based partitioning by `time_column` | Exposes time boundaries | Time buckets, then quantile within buckets |
| `auto` | Defaults to `quantile` | Same as quantile | Same as quantile |

Use `strategy: hash` when key values are sensitive (PII, financial IDs) and you want privacy-safe comparison without exposing any actual key values at the top level.

Use `strategy: time` with `time_column` and `time_granularity` (hour, day, week, month, quarter, year) to partition by time periods.

### Privacy Levels

| Level | Data Retrieved | Use Case |
|-------|---------------|----------|
| `count_only` (default) | COUNT(*), SUM(checksum) | Detect differences without exposing data |
| `with_keys` | + Primary keys of differing rows | Identify which rows differ |
| `detailed` | + Sample row values | Debug specific differences |

`detailed` additionally requires `reporting.consent_acknowledged: true`, and `sample_limit` caps how many rows either non-default level returns.

## Audit Logs

An audit log is the full record of a run — every query, timing, count, checksum and mismatch leaf — written as JSON by `--audit-log`. Its structure is the [AuditLog JSON schema](https://schemas.synq.io/synq-recon/v1/audit-log.schema.json), generated from the `synq/agent/recon/v1` `AuditLog` proto. Reading one, and the field-casing difference between a local file and a log fetched from the workspace, are covered in [the operating guide](AGENTS.md) § Reading the output.

### Where a Run's Results Go

A locally executed run reports its audit log to Coalesce Quality whenever it can resolve a credential — client credentials, `QUALITY_TOKEN`, or a stored browser login — so results show up in the workspace alongside runs the backend executed. This happens even when every database in the suite is local, and the run says so at `INFO`, naming the endpoint.

`--no-report` (or `RECON_NO_REPORT`) keeps a run entirely local: no credential is resolved and no connection is opened, so `--audit-log` and the terminal are the only outputs. This is the mode for a standalone or air-gapped comparison, where only counts and checksums leave the database and even those stay on the machine.

Reporting also needs the `SCOPE_INGEST_RECON` permission. A credential without it produces a single warning naming the remedy — the comparison itself has already happened and its result is unaffected.

### Regenerating Example Audit Logs

The `audit-logs/` directory is gitignored. Regenerate locally:

```bash
./examples/generate-audit-logs.sh
```

## Development

```bash
# Run tests
go test ./...

# Run with verbose
go test -v ./...

# Run specific test suite
go test ./pkg/reconciler/... -run TestDuckDBReconcilerTestSuite -v

# Run all example/test validations end-to-end
./examples/test-all-examples.sh
```

The audit-log JSON schema is generated from the `synq/agent/recon/v1` `AuditLog` proto by
`dev-helpers/generate-public-schemas/generate.py` in the `getsynq/cloud` monorepo (not from this
module) and published to https://schemas.synq.io/synq-recon/v1/audit-log.schema.json.

## License

Copyright (c) Coalesce Software, Inc. All rights reserved.
