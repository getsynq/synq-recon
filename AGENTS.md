# Driving `synq-recon`

This guide tells a coding agent how to use `synq-recon` on a reconciliation
suite. Read it from the top down.

A **reconciliation** compares one dataset in a source database with one dataset
in a target database. A **suite** is a YAML file with several reconciliations
and their connections. By default, only counts and checksums leave the
database, never row values.

---

## 1. The loop

Do these steps in order. Do not skip a step, because each step costs more than
the step before it.

### Step 1: validate offline with `check-config suite.yaml`

The command checks the YAML and warns about time-dependent SQL. It connects to
no database. Continue when it prints `Configuration check passed!`. A warning
about `NOW()` or `CURRENT_DATE` is real, see [Never do these](#2-never-do-these).

### Step 2: read the plan with `plan suite.yaml`

The command prints the exact SQL of each side after variables, table references
and time-travel snapshots resolve. It connects to no database. Continue when the
SQL is the SQL you meant. This is the cheapest place to find a wrong date or a
wrong schema. Values that a run derives from live data, such as a cutoff
watermark, are named but not resolved.

### Step 3: validate against the databases with `check-config suite.yaml --db`

The command sends each query to the query planner (`LIMIT 0`). It reports the
columns, the table size, the keys and a suggested key column, and warns when
your key column has no index. Continue when every connection is `OK` and every
query validates. `--db` does not run the `setup:` SQL. If `setup` creates the
tables, every query fails here, so go to step 4.

### Step 4: compare with `run-check suite.yaml`

The command compares each reconciliation without a drill, with one query per
side. If it reports `MATCH`, the datasets agree and you are done. If
it reports `MISMATCH`, go to step 5. Exit code 1 is a result, not a failure.
Exit code 2 means that a reconciliation could not run, so read its error first.

### Step 5: locate with `run suite.yaml --auto-drill`

The command runs the check, then bisects the key space of each mismatch to find
the key ranges that differ. `run-drill` does the same without the check.
Continue when the drill reports usable key ranges. If it reports thousands of
leaves, stop and read [Never do these](#2-never-do-these).

### Step 6: save to the workspace with `upload-config suite.yaml`

Run `auth whoami` first. The command stores a version of the suite in your
Coalesce Quality workspace, under **Development**, and prints the suite id.

### Step 7: run on the backend with `run-remote <suite-id> --wait`

Coalesce Quality runs the suite against the workspace integrations. Connections
bind to integrations by name, or explicitly with
`--map connection=integration_id`. Pass `--drill=false` if you do not want a
drill.

### Step 8: publish to production with `promote <suite-id>`

The command creates a deployment: a snapshot of the suite and an optional
schedule. Its results become assets, checks and issues. If you edit the suite,
production does not change until you promote again. Run `promote --diff` first,
see [Editing a deployment](#editing-a-deployment).

### After a run

`recheck <run>` runs the same queries again and reports what changed.
`drill-deeper <run>` continues the drill, see
[Investigating a finished run](#7-investigating-a-finished-run).

---

## 2. Never do these

- Do not query the warehouse by hand to "check something first". Write the
  question as a reconciliation, so that the result is recorded and
  reproducible. If the tool cannot express it, report a bug.
- Do not commit `.connections.yaml` or any credential. Keep the real file in
  `.gitignore`. Commit only a `.connections.yaml.example` with `${ENV_VAR}`
  placeholders. Do not `upload-config` a suite that holds a literal secret.
- Do not run a drill with threshold 1 on a table with tens of thousands of real
  differences. Bisection is O(log n) only when most rows are identical. When
  most rows differ, it sends thousands of queries that each scan a large part
  of the table. First find the groups that differ with an aggregate comparison
  (`mode: aggregate`, a `COUNT` measure grouped by the natural partition). Then
  drill a query that reads only those groups.
- Do not omit `--drill` on `run-remote` if you want no drill. An ad hoc run has
  no deployment to inherit from, so it drills every mismatch whose
  reconciliation has `bisection.enabled: true`, the default. Pass
  `--drill=false`. Only `run-drill` and `drill-deeper` drill a reconciliation
  with `bisection.enabled: false`.
- Do not put `NOW()`, `CURRENT_DATE` or `GETDATE()` in a query. The two sides
  evaluate them at different instants, which makes false differences. Use a
  template variable such as `{{ today - 7d }}`, which resolves once for both
  sides. `strict_time_references: true` makes the `check-config` warning an
  error.
- Do not make a concatenated key such as `a || '|' || b`. It cannot use an
  index, so each segment scans the full table. Write
  `key_columns: [workspace, path]`, and bisection filters on the column tuple.
- Do not compare a replica that lags without a `cutoff:`, see
  [Avoiding false differences](#avoiding-false-differences).

---

## 3. Confirm the target before any mutation

Each command that writes to a workspace acts on the workspace of your
credential: `upload-config`, `promote`, `unpromote`, `trigger`, `run-remote`,
`deployment …`, `suite delete` and `runs cancel`.

```bash
synq-recon auth whoami
```

Before the mutation, read the `workspace:` line and confirm it is the correct
workspace. There is no `--workspace` flag. To change the target, change the
credential.

### Credential order

The CLI uses the first credential it finds, so an automated pipeline never uses
the browser login of a developer:

1. Client credentials: `--client-id` / `--client-secret`, or
   `QUALITY_CLIENT_ID` / `QUALITY_CLIENT_SECRET`, or the `synq:` block of the
   suite.
2. An API token: `QUALITY_TOKEN`.
3. The browser login from `synq-recon auth login`. The CLI refreshes it
   automatically.

To log in with a Coalesce account, see `synq-recon auth login --help`. That
credential carries your Coalesce Quality roles, not the permissions below.

The `--synq-` flags and the `SYNQ_` environment variables are older spellings
and still work.

### Region and endpoint

`--region eu|us|au` and `--endpoint` (or `QUALITY_API_ENDPOINT`, for staging or
self-hosted) are root flags. They also select the stored credential of that
region, and a token never goes to another region. Usually you need neither:
`auth login --region au` records the deployment for later commands, and
`auth use <region>` or `auth use --clear` changes it. The order is
`--endpoint`, `--region`, the `synq.endpoint` of the suite,
`QUALITY_API_ENDPOINT`, `QUALITY_REGION`, the last login, then `eu`.

### Permissions

`SCOPE_RECON_READ` lets you inspect. `SCOPE_RECON_EDIT` lets you
`upload-config`, edit suites and report the results of a local run.
`SCOPE_RECON_PROMOTE` lets you promote and trigger. A workspace API client can
have all three, so every command works without a person.

---

## 4. Authoring a suite

The smallest useful suite is a connection pair and one reconciliation:

```yaml
name: orders-consistency
title: "Orders consistency"

connections:
  gateway:
    postgres:
      host: db.internal
      port: 5432
      database: payments
      username: ${PG_USER}
      password: ${PG_PASSWORD}
  warehouse:
    snowflake:
      account: myorg.us-east-1
      warehouse: COMPUTE_WH
      role: ANALYST
      username: ${SF_USER}
      password: ${SF_PASSWORD}
      databases: [ANALYTICS]

reconciliations:
  orders-daily:
    source:
      connection: gateway
      table: public.orders
    target:
      connection: warehouse
      table: ANALYTICS.PUBLIC.ORDERS
    key_columns: [order_id]
    mode: row_checksum
```

[Authoring suites](https://docs.synq.io/reconciliation/authoring-suites) and
[Comparison modes](https://docs.synq.io/reconciliation/comparison-modes) explain
each part. The [Configuration reference](https://schemas.synq.io/synq-recon/v1/config.html)
lists every field, type and default. For completion and validation in your
editor, point it at the schema:

```yaml
# yaml-language-server: $schema=https://schemas.synq.io/synq-recon/v1/config.schema.json
```

### Rules that decide if a suite works

- Use `table:` when you can. The tool then finds the columns, and you can narrow
  with `columns:`, `exclude_columns:` and `where:`. Use `query:` only when the
  comparison needs SQL. A `query:` takes `columns:` and `exclude_columns:` too.
  A cutoff filters the query as written, so its column need not be in
  `columns:`. `where:` is for a `table:` only. A suite with `where:` beside a
  `query:` does not load, so put the filter in the query.
- `exclude_columns:` matches a name in any case, quoted or bare. The run warns
  about an entry that matches no column, because it excludes nothing.
- Key columns must be unique and should have an index, because bisection sorts
  and filters on them. Keep them in the `columns:` of each side and out of
  `exclude_columns:`. If a side leaves a key column out, the drill fails at the
  first difference.
- Each mode except `row_count` needs the same number of columns on both sides,
  because the checksum hashes the columns by position. A wider target fails with
  `source has N columns but target has M columns`. Narrow both sides with
  `columns:`, or remove the extra columns with `exclude_columns:`. `row_count`
  reads no columns, so it needs only the key columns on both sides.
- Names that differ only in case match automatically. For other names, use
  `column_mapping`.
- Write a name as you write it unquoted, and quote only to pin it. The tool
  quotes each part of `table:` and each entry of `columns:` for its warehouse,
  so a reserved word such as `order` works. An unquoted name resolves as the
  warehouse resolves it: `orders` is `ORDERS` on Snowflake and `orders` on
  Postgres. For a name created with quotes, quote that part:
  `table: 'DB.SCH."events"'`. The outer single quotes are YAML syntax.
  `key_columns`, `column_mapping` and `cutoff:` match column names in any case.
- Keep credentials in `.connections.yaml`, keyed by the connection names. The
  CLI finds it automatically, or you pass `--connections`. In the workspace, the
  same names bind to integrations, so one suite runs in both places.
- Do not set `motherduck_account`, the CLI sets it. Write the MotherDuck
  account name in `database:`, and pass `motherduck_token`.

### Finding the physical table path

If the warehouse is an integration of your workspace, the catalog finds the
physical `database.schema.table` of a side:

```bash
synq-recon entities search orders --type snowflake_table
synq-recon entities resolve ANALYTICS.PUBLIC.ORDERS
```

Both print the `database`, `schema` and `table`, and the dialect and connection
id, to choose between warehouses with the same name. The catalog is optional. A
DuckDB file or a local container is not in it, and no other command reads it.

### Avoiding false differences

Most "the data is wrong" findings are a problem with the comparison window. Try
these first. [Time windows and cutoffs](https://docs.synq.io/reconciliation/time-windows-and-cutoffs)
explains `cutoff:`, `window:` and `variables:`.

| Symptom | Use | What it does |
|---|---|---|
| The target lags the source, so the newest rows look missing | `cutoff:` | Finds a watermark in the data (`min` of the two sides by default) and filters both sides to it. |
| Only a recent period matters | `window:` | Compares a lookback period. In a query, use `{{window_start}}` / `{{window_end}}`. |
| Queries need a date or id boundary | `variables:` | Resolves once, goes into both sides. Override with `--var key=value`. |
| You compare with a snapshot at a point in time | `as_of:` | Sends a time-travel query. |
| Numbers differ only after some decimal place | `comparison:` | `numeric_scale: <places>` rounds both sides. |
| Timestamps differ only in fractions of a second | `comparison:` | `timestamp_precision: second` (or `millisecond`, `microsecond`) cuts both sides. |
| Timestamps without a time zone differ by whole hours | `comparison:` | `source_time_zone:` / `target_time_zone:` give the IANA zone of the wall clocks of a side. |

### Numeric and timestamp precision

[Comparison modes](https://docs.synq.io/reconciliation/comparison-modes#numeric-precision)
gives the defaults, the precedence and examples. The traps:

- `numeric_scale: <places>` rounds half away from zero. It is not a tolerance:
  `10.1249` and `10.1250` round to different values at two places.
- `numeric_scale: exact` fails if the two sides declare different scales. On a
  floating-point column, it works only between two databases of the same kind.
- `comparison:` applies to `row_checksum` only. Other modes ignore it with a
  warning.
- `check-config --db` reports every column that `exact` cannot compare. A run
  stops at the first one.

---

## 5. Reading the output

### Output formats

Set the format explicitly. `-o` is `table` in a terminal and `toon` when the CLI
finds an AI agent environment. To parse output, pass `-o json`.

`run`, `run-check` and `run-drill` have only two formats: `-o json` and a text
report. `--jq`, `--columns`, `--no-headers` and `--wide` have no effect on them,
so send their `-o json` to `jq`. The workspace commands accept every format and
these four flags.

`run --auto-drill -o json` is not one JSON document. It prints the check
document, a text banner, then one drill document for each reconciliation. To
parse the results, run `run-check -o json` and `run-drill -o json` separately.
Each prints one document. The results of an `aggregate` reconciliation are a
separate array, so `--include` one mode at a time.

```bash
# names that differ
synq-recon run-check suite.yaml -o json | jq -r '.results[] | select(.match == false) | .name'

# key ranges of each difference
synq-recon run-drill suite.yaml --include orders-daily -o json \
  | jq -r '.mismatch_leaves[] | "\(.segment.min_key) .. \(.segment.max_key)"'

# SQL for one difference, both sides
synq-recon run-drill suite.yaml --include orders-daily -o json \
  | jq -r '.investigation_queries[0] | .source_query, .target_query'
```

Logs go to stderr and results go to stdout. When you pipe `-o json`, use
`2>/dev/null`, never `2>&1`.

### Exit codes

Each code has the same meaning in every command:

| Code | Meaning |
|---|---|
| `0` | Everything matched. For `run-remote --wait` and `trigger --wait`: no `--fail-on` status occurred. |
| `1` | The data differs. For a remote run with `--wait`: a `--fail-on` status occurred (by default `mismatched` and `failed`). |
| `2` | The run, or one of its reconciliations, could not run: a connection, a query or a timeout. |
| `3` | The command failed before it had a result: a bad flag or config, a refused credential, an API error, or an expired `--wait-timeout`. |

A local run with a difference and a failed reconciliation exits `2`. Thus `1`
always means that every reconciliation has a result. A remote run that
completes can still report a mismatch, which is normal. `--fail-on` takes
several statuses, separated by commas or with the flag repeated
(`--fail-on mismatched,within_threshold`). The list replaces the default.
`--fail-on=passed` makes a check for data that must differ.

### Audit logs

`--audit-log <path>` writes the full record of a run as JSON: every query,
timing, count, checksum and mismatch leaf. For a file name made by the CLI,
give a directory with a trailing `/`. The format is the AuditLog schema,
[rendered](https://schemas.synq.io/synq-recon/v1/audit-log.html) or as
[`audit-log.schema.json`](https://schemas.synq.io/synq-recon/v1/audit-log.schema.json).

```bash
jq -r '.reconciliations[].reconciliation.name' audit.json
jq -r '.reconciliations[].stages[].quick_check_result? | select(.) | "\(.source_count) vs \(.target_count)"' audit.json
jq -r '.reconciliations[].stages[].bisection_result?.mismatch_leaves[]?.segment | "\(.min_key)..\(.max_key)"' audit.json
```

Each mismatch leaf has a `drill_stop_reason`, `diff_queries` with SQL for both
sides, and all the `mismatch_types` that apply:

| Value | Meaning |
|---|---|
| `SEGMENT_MISMATCH_TYPE_MISSING_IN_TARGET` | Rows on the source, none on the target: a real gap. |
| `SEGMENT_MISMATCH_TYPE_MISSING_IN_SOURCE` | Rows on the target, none on the source: usually an orphan. |
| `SEGMENT_MISMATCH_TYPE_COUNT_MISMATCH` | Rows on both sides, but different counts. |
| `SEGMENT_MISMATCH_TYPE_DATA_MISMATCH` | Rows on both sides, and the checksums differ: a value changed. |

Do not classify a difference by the count only. A target with one more row can
still miss a row and hold two orphans. Read the types.

Two traps in the audit log:

- The local `--audit-log` file uses snake_case (`bisection_result`). The same
  log from `audit-logs get <invocation-id> -o json` uses camelCase
  (`bisectionResult`). A `jq` path for one returns `null` on the other.
- Counts and checksums are 64-bit integers, which the audit log writes as
  strings (`"source_count": "10"`). `run-check -o json` writes numbers. Use
  `tonumber` to compare.

---

## 6. What each command costs

On a warehouse that charges for use, each query of a run costs money. Know the
cost before you put a command in a loop.

| Command | Warehouse cost |
|---|---|
| `check-config`, `plan`, `upgrade`, and the workspace commands except the two below | None. |
| `check-config --db` | One planner call per query (`LIMIT 0`, no scan) and a read of table metadata. |
| `run-check` | One aggregate query per side. An `aggregate` reconciliation sends one grouped query per side for each group column it descends into. |
| `run-drill`, `run --auto-drill` | For each segment it splits: a count and checksum per side, a boundary query and one bucketed query per side. |
| `recheck`, `drill-deeper` | The same as the stage they replay, but only for what is still open. |
| `run-remote`, `trigger` | The cost of the run, spent by the backend against workspace integrations. |

### Cost traps

- The table analysis of `check-config --db` can grow with the warehouse, not
  with the suite. On BigQuery, and other platforms without a metadata API per
  table, it reads the metadata of whole datasets. On a large warehouse this is
  slow and costs money. Thus only `check-config --db` runs it.
- `--max-table-rows` and `--max-table-bytes` make `run`, `run-check` and
  `run-drill` estimate each scan first, with a dry run or `EXPLAIN`. The CLI
  warns when an estimate is above the limit. Both are `0` (off) by default.
  BigQuery and Snowflake estimate bytes. ClickHouse and PostgreSQL estimate
  rows. DuckDB, Athena and Databricks give no estimate, so no warning occurs.

### Limiting the load of a local run

- `--concurrency` sets how many reconciliations run at the same time. Each
  reconciliation queries both sides, and a drill can query many segments at the
  same time.
- `connections.<name>.parallelism` sets the maximum number of queries a local
  run sends to that connection at the same time. The default is `8`.
- `connections.<name>.disabled: true` stops a local run from running a
  reconciliation, setup or teardown that uses that connection. If `--include`
  names such a reconciliation, the command fails.

These connection settings apply only to local runs. A suite in the workspace
uses integrations.

### Keeping a local run local

If a stored credential exists, a local run reports its results to Coalesce
Quality, even when all its databases are local. It logs the endpoint at `INFO`,
and prints a link to the stored run to stderr. A reported run never sends row
values. To send nothing and resolve no credential, pass `--no-report` or set
`RECON_NO_REPORT`.

`reporting.level: detailed` is for local runs only. Coalesce Quality does not
save, promote or run a suite with `detailed`. In a workspace suite, use
`with_keys` or `count_only`. To keep `detailed` and local fixtures in the same
file, put them in a `local:` block, see
[Settings for local runs only](https://docs.synq.io/reconciliation/authoring-suites#settings-for-local-runs-only).
`upload-config` and **Upload config** in the app drop the `local:` block, so the
workspace never runs your fixtures.

---

## 7. Investigating a finished run

`audit-logs queries`, `recheck` and `drill-deeper` take a finished run, not a
suite. The run is a local audit log file or the invocation id of a stored run.

### Getting the SQL back

`audit-logs queries <run>` prints the investigation queries of a finished run:
a stored run, a backend run, or a run whose output you lost. It connects to no
warehouse.

```bash
# SQL for each difference the run found, both sides
synq-recon audit-logs queries audit.json

# One reconciliation of a stored run
synq-recon audit-logs queries 3f7c1e28-5a1b-4c9e-9f10-2b7d8e6a4c53 --include orders-daily

# The queries the run sent, in stage order
synq-recon audit-logs queries audit.json --executed

# One side, to a client
synq-recon audit-logs queries audit.json -o json | jq -r '.[0].source_query'
```

A bisection drill gives one query pair for each range of adjacent mismatched
segments. `--all-leaves` also prints the query of each segment. An aggregate
comparison gives one pair for each group that differs. A run that matched, or
did not drill, has no queries.

### Replaying a run

```bash
# Is the difference gone? (for example, after a backfill)
synq-recon recheck audit.json --connections .connections.yaml

# Narrow each open segment to ranges of 100 rows
synq-recon drill-deeper audit.json --connections .connections.yaml --threshold 100

# Split each aggregate group that differs by one more column
synq-recon drill-deeper audit.json --add-group-column region
```

A replay sends the queries of the original run, with the same variables and
cutoffs, so it compares the same window. To use an edited query or the current
data, pass `--reresolve`. An `as_of` snapshot needs `--reresolve`, or it can
never pass. An audit log holds connection names, never credentials, so pass
`--connections`. `--remote` sends the replay to the backend, and needs the
invocation id of a stored run. [Re-check and Drill deeper](https://docs.synq.io/reconciliation/investigating-results#re-check-and-drill-deeper)
gives the other rules.

---

## 8. Command reference

`synq-recon <command> --help` is the full reference, and the
[CLI reference](https://docs.synq.io/reconciliation/cli) page has the same
content. This section is the map.

| Command | What it does |
|---|---|
| `check-config <file>` | Validates a suite. `--db` also connects. |
| `plan <file>` | Prints the resolved SQL of each side, without a run. |
| `run-check` / `run-drill` / `run <file>` | Stage 1 (compare), stage 2 (bisect), or both with `--auto-drill`. |
| `recheck` / `drill-deeper <run>` | Replays a finished run, see [Investigating a finished run](#7-investigating-a-finished-run). |
| `dump-suite <file>` | Prints the parsed suite as protojson, for debugging. |
| `upgrade` | Replaces this binary with the latest verified release. |
| `auth login` / `logout` / `status` / `token` / `whoami` / `use` | Manages the credential, see [Confirm the target](#3-confirm-the-target-before-any-mutation). |
| `upload-config <file>` | Saves a suite to Development. It copies the SQL of each `setup_file` and `teardown_file` into the suite, and drops the `local:` blocks. |
| `suite …` | Manages stored suites. `suite yaml` gives an editable YAML file. |
| `connections remote list` / `bootstrap` | Lists workspace integrations, and makes a matching `.connections.yaml`. |
| `entities search` / `resolve` | Finds the physical path of a table in the catalog. |
| `run-remote <suite-id>` | Starts an ad hoc backend run. |
| `promote` / `unpromote <suite-id>` | Publishes to Production, or stops a deployment and keeps its history. |
| `trigger <suite-id>` | Runs a deployment now. A retry with the same `--invocation-id` returns the first run. |
| `deployment …` | Shows and edits deployments. |
| `runs …`, `audit-logs …` | Shows and cancels runs, and shows stored results. |

### Editing a deployment

`promote` on an existing deployment, and `deployment update`, change only the
settings you pass. Thus a new snapshot never removes the schedule or the API
trigger. To remove a schedule, pass `deployment update --clear` or
`promote --clear-schedule`. A first promote uses the defaults: no schedule, no
API trigger, and drill on.

Run `promote <suite-id> --diff` before each promote. A promote replaces what
production runs, and the only undo is another promote:

```bash
synq-recon promote orders-suite --diff --schedule '0 * * * *' --timezone UTC
```

It prints a YAML diff of the deployed snapshot against the stored suite. Then it
labels each deployment setting: `changed`, `unchanged`,
`preserved (flag not passed)`, or the default of a first promote. Without these
labels, an omitted `--schedule` and a removed schedule look the same.

The deployment id is part of the asset path of each reconciliation. A new
deployment with a new id moves its checks and drops their history. A promote of
the same suite uses the same id. To set the id when you rebuild a deployment,
use `promote --deployment-id <id>`.

### Check categories

Set a check category on the deployment, not in the suite file, because a
reconciliation is a check only after a promote. `--category` is the technical
category and `--governance-category` is what the check is for, see
[Check categories](https://docs.synq.io/analytics/check-categories).

```bash
synq-recon promote orders-suite --category comparison --governance-category accuracy
synq-recon deployment set-categories orders-suite --case-governance-category row-counts=completeness
```

An omitted flag keeps the stored value. An empty value (`--category ""`)
removes the declaration. A case overrides only the categories you name. Without
a declaration, a `quality.check_category` / `quality.governance_category`
annotation decides, else the categorisation rules of the workspace.

### Flags with traps

- `--timeout` is the time limit of a local run. The default is the
  `execution.timeout` of the suite, else `5m`. The time limit of a backend run is
  `--execution-timeout`, which falls back to the deployment, then to
  `execution.timeout`. For one reconciliation, set
  `execution.reconciliation_timeout` on the suite or `timeout` on the
  reconciliation. Such a reconciliation fails with a timeout, and the run
  continues.
- `--concurrency` falls back to `execution.concurrency`, else `1`. Backend runs
  read `execution.concurrency` and can use a lower limit.
- `--connections` finds `.connections.yaml` or `connections.yaml` in the working
  directory automatically. `--dbt-profiles` reads connections from a dbt
  `profiles.yml` if the suite does not define them.
- `--force` skips safety checks too, not only confirmation prompts.

---

## 9. Worked example

This example uses the DuckDB fixtures in `examples/` of a release archive. It
needs no warehouse, credentials or network. The suite has two differences on
purpose: one missing order and one wrong amount.

1. Validate:

   ```bash
   ./synq-recon check-config examples/ecommerce.yaml
   # Configuration check passed!
   ```

2. Compare:

   ```bash
   ./synq-recon run-check examples/ecommerce.yaml --include ecommerce-orders --no-report
   ```

   ```
   Reconciliation: E-Commerce Orders (Payment Gateway vs Warehouse) (ecommerce-orders)
   Mode: row_checksum

                Source              Target
   Row Count    10                  9

   Status: MISMATCH
     - Source has 1 more rows than target

   Hint: Run 'synq-recon run-drill <config> --include ecommerce-orders' to locate differences.
   ```

   The exit code is 1: differences found, as expected.

3. Locate the differences and keep the audit log:

   ```bash
   ./synq-recon run examples/ecommerce.yaml --include ecommerce-orders \
     --auto-drill --no-report --audit-log /tmp/orders.json
   ```

   ```
   Depth 0: Segment [*, *)
     Source: 10 rows, checksum: -139824023944409
     Target: 9 rows, checksum: -144133400916972
     Status: MISMATCH -> drilling down (2/10 rows in mismatched segments)
     Depth 1: Segment [1,005, 1,006)
       Source: 1 rows, checksum: 53805022444628
       Target: 0 rows, checksum: 0
       Status: MISMATCH (leaf: threshold_reached)
     Depth 1: Segment [1,010, 1,011)
       Source: 1 rows, checksum: 20466544489071
       Target: 1 rows, checksum: 69962189961136
       Status: MISMATCH (leaf: threshold_reached)
   ```

   Order 1005 is missing on the target. Order 1010 is on both sides, but its
   checksum differs, so a value changed. Only two of ten rows needed a look.

4. Get the SQL that shows the rows, and run it on the two connections:

   ```bash
   ./synq-recon run-drill examples/ecommerce.yaml --include ecommerce-orders \
     --no-report -o json 2>/dev/null \
     | jq -r '.investigation_queries[] | .source_query, .target_query, "--"'
   ```

5. Check again after a fix. The suite defines its connection, so a replay needs
   a connections file with that name:

   ```bash
   printf 'connections:\n  test-db:\n    duckdb:\n      database: ":memory:"\n' > /tmp/conn.yaml
   ./synq-recon recheck /tmp/orders.json --connections /tmp/conn.yaml --no-report
   ```

   ```
   RECONCILIATION    BEFORE       AFTER        CHANGE
   ----------------  -----------  -----------  ------------------------------------------
   ecommerce-orders  mismatched   mismatched   still mismatched (row gap unchanged at -1)
   ```

   Nothing changed because nothing was fixed.

6. Try the aggregate mode, which finds a difference by group, not by key range:

   ```bash
   ./synq-recon run examples/ecommerce.yaml --include inventory-reconciliation \
     --auto-drill --no-report
   ```

[`examples/`](examples/) has one scenario for each business case.
`./examples/test-all-examples.sh` runs all of them.

---

## 10. When something goes wrong

| What you see | What it means |
|---|---|
| `Validation failed: no connections defined` from offline `check-config` | The `connection:` fields are workspace integration ids. Pass `--connections <file>`, and add `--db` to connect. |
| `no connections available to replay run …` | Pass `--connections` to `recheck` or `drill-deeper`. |
| `accepts 1 arg(s), received 2` | You gave a reconciliation name as an argument. Use `--include <name>`. |
| `grouping by <columns> produced more than … groups` | The grouping has almost one group per row, usually because `group_columns` is not set and the key column is used. Group by a coarser column, set neither `group_columns` nor key columns to compare totals, or use `row_count` or `row_checksum`. |
| A warning that the stored credential has no scope | The command works if it has the scope it needs. Without the reporting scope, a local run does not report its results. |
| `deployment is not active; re-promote to modify` | The deployment was unpromoted. Promote again before you change or remove it. |
| `N connection(s) could not be bound to an integration` | No workspace integration has the connection name, or it is not allowed for reconciliation. Check with `connections remote list`, or bind with `--map name=integration_id`. |
| `-o json` output does not parse | See [Output formats](#output-formats). |
| Oracle fails with `ORA-01489: result of string concatenation is too long` and names `GRANT EXECUTE ON SYS.DBMS_CRYPTO` | A row is longer than 4000 bytes, and the user cannot call `DBMS_CRYPTO`, which longer rows need. A database administrator runs `GRANT EXECUTE ON SYS.DBMS_CRYPTO TO <user>`. |
| `type: duckdb` fails in the Docker image | That image has no CGO. Pull `:latest`, or use a binary that you built. |
