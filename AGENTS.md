# Driving `synq-recon`

This is the operating guide for a coding agent using `synq-recon` to author,
validate, run, promote and investigate a reconciliation suite: the loop to
follow, the mistakes that cost real time, how to read the output, and what each
command spends. It is written to be acted on top-down.

A **reconciliation** compares one dataset in a source database against one in a
target database and reports whether they agree. A **suite** is a YAML file
holding several reconciliations plus the connections they use. Only counts and
checksums leave the database by default — no row values.

---

## 1. The loop

Work through these in order. Each step has a condition for moving on; do not
skip ahead, because every later step is more expensive than the one before it.

**1. Validate offline — `check-config suite.yaml`**

Parses the YAML, checks required fields, and warns about time-dependent SQL.
Costs nothing, touches no database.

> Move on when it prints `Configuration check passed!`. Fix errors here rather
> than discovering them mid-run. Warnings about `NOW()` / `CURRENT_DATE` are
> real — see [Never do these](#2-never-do-these).

**2. Validate against the databases — `check-config suite.yaml --db`**

Connects to every connection, runs each query through the database's query
planner (`LIMIT 0`), and reports the resolved columns. It also reports table
size, primary/partition keys, a suggested key column, and warns when the key
column you chose is not indexed.

> Move on when every connection is `OK` and every query validates. A failure
> here is a wrong table name, a missing grant, or a column that does not exist —
> all of which would otherwise surface as a confusing mid-run error.
>
> `--db` does **not** run the suite's `setup:` SQL, so a suite whose tables are
> created by `setup` will report every query as failed. That is expected; skip
> to step 3 for such suites.

**3. Compare — `run-check suite.yaml`**

One query per side: total row count and checksum. Fast and cheap regardless of
table size.

> If it reports `MATCH`, the datasets agree and you are done.
> If it reports `MISMATCH`, go to step 4. Exit code 1 means "differences found",
> which is a result, not a failure.

**4. Locate — `run suite.yaml --auto-drill`**

Runs the quick check, then bisects the key space on whatever mismatched to
narrow the difference to specific key ranges. `run-drill` does the same without
re-running the quick check.

> Move on when the drill reports mismatch leaves with usable key ranges. If it
> reports thousands of leaves, stop and read
> [Never do these](#2-never-do-these) — you are drilling something that should
> be localised with an aggregate comparison first.

**5. Save to the workspace — `upload-config suite.yaml`**

Stores and versions the suite in your Coalesce Quality workspace, where it
appears under **Development**. Requires `SCOPE_RECON_EDIT`.

> Run `auth whoami` first. Move on when it prints the suite id.

**6. Run it on the backend — `run-remote <suite-id> --wait`**

Executes the suite in Coalesce Quality against workspace integrations rather
than against databases this machine can reach. Connections bind to integrations
by name; override with `--map connection=integration_id`.

> Move on when the run completes. `--wait` exits `0` if everything passed, `1`
> if a `--fail-on` condition was hit, `2` if execution itself failed.
> **Pass `--drill=false` explicitly if you do not want a drill** — omitting the
> flag does not mean "off".

**7. Publish to production — `promote <suite-id>`**

Creates a deployment: an immutable snapshot of the suite plus an optional
schedule, so it runs on its own and its results become platform assets, checks
and issues. Requires `SCOPE_RECON_PROMOTE`.

> A deployment is a snapshot, not a pointer: editing the suite afterwards
> changes nothing in production until you re-promote. Re-promoting preserves
> settings you omit; a *fresh* promote applies defaults, and the drill default
> on a fresh promote is **on**.

**Any time after a run:** `recheck <run>` re-executes what it ran and reports
what moved; `drill-deeper <run>` continues its drill from where it stopped. Both
take a local audit-log file or the invocation id of a stored run. See
[Investigating a finished run](#7-investigating-a-finished-run).

---

## 2. Never do these

Each of these has already cost someone real time.

**Do not hand-query the warehouse to "check something first."** Express the
question as a reconciliation and let `synq-recon` run it — that way the result
is recorded, reproducible, and comparable to the next run. If the tool cannot
express what you need, that is a bug worth reporting, not a reason to open a SQL
client.

**Do not commit `.connections.yaml`, or any credential, ever.** Keep the real
file git-ignored and commit only a `.connections.yaml.example` whose values are
`${ENV_VAR}` placeholders. A suite YAML with a literal secret in it is also a
suite you cannot safely `upload-config`.

**Do not run a threshold-1 drill over a table with tens of thousands of genuine
differences.** Bisection is O(log n) when the data is *mostly* identical; when
most rows differ it cannot halve, and it degenerates into thousands of queries
that each rescan a large slice of the table. Localise first: an aggregate
comparison (`mode: aggregate`, a `COUNT` measure grouped by the natural
partition) tells you *which* groups diverge in roughly one query per side. Then
drill a query narrowed to those groups.

**Do not omit `--drill` on `run-remote` and expect no drill.** Unlike `promote`,
where an omitted flag preserves the stored setting, an ad-hoc run has no
deployment to inherit from, so an omitted `--drill` falls through to each
reconciliation's own `bisection.enabled` in the YAML. Pass `--drill=false`.

**Do not put `NOW()`, `CURRENT_DATE` or `GETDATE()` in a query.** They evaluate
at slightly different instants on the two sides, which manufactures differences
that are not there. Use a template variable, resolved once and interpolated into
both sides:

```yaml
variables:
  start_date: "{{ today - 7d }}"
  end_date: "{{ today }}"
```

`check-config` warns about this; `strict_time_references: true` makes it an
error.

**Do not synthesise a concatenated key.** For a multi-column natural key, declare
`key_columns: [workspace, path]`. Bisection then orders and range-filters on the
column *tuple*, so a matching primary key or index still prunes each segment. A
synthetic `a || '|' || b` key cannot use the index and forces a full scan per
segment.

**Do not compare a lagging replica without a cutoff.** If the target trails the
source, rows still in flight look like missing rows. A `cutoff:` derives a
watermark from the data itself and filters both sides to at-or-below it. See
[Cutoffs](#avoiding-false-differences).

---

## 3. Confirm the target before any mutation

Every command that writes to a workspace — `upload-config`, `promote`,
`unpromote`, `trigger`, `run-remote`, `deployment …`, `suite delete`,
`runs cancel` — acts on whichever workspace your credential resolves to.

```bash
synq-recon auth whoami
```

Read the `workspace:` line and confirm it is the one you mean **before** the
mutation, not after. There is deliberately no `--workspace` override: your
credential determines the target, so the way to change it is to change the
credential.

Credentials resolve in a fixed order, so an automated pipeline never silently
picks up a developer's browser login:

1. Client credentials — `--client-id` / `--client-secret`, or
   `QUALITY_CLIENT_ID` / `QUALITY_CLIENT_SECRET`, or the `synq:` block in the suite.
2. An API token — `QUALITY_TOKEN`.
3. The browser login cached by `synq-recon auth login`, refreshed automatically.

`--region eu|us|au` selects the deployment, and `--endpoint` (or
`QUALITY_API_ENDPOINT`) points at a staging or self-hosted one. Both are root
flags, so they work on every command. Whichever you use also selects *which
region's* stored credential is used — a token minted for one region is never
sent to another.

You rarely need either: `synq-recon auth login --region au` records the
deployment, and later commands resolve to it. `synq-recon auth use <region>`
switches between deployments you are already logged in to, and
`auth use --clear` goes back to the default (`eu`). Resolution order is
`--endpoint` > `--region` > the suite's `synq.endpoint` > `QUALITY_API_ENDPOINT`
> `QUALITY_REGION` > the last login > `eu`.

The `--synq-`-prefixed flags and `SYNQ_`-prefixed variables are the previous
spellings and still work.

Permissions: `SCOPE_RECON_READ` to inspect, `SCOPE_RECON_EDIT` for
`upload-config`, suite edits and reporting a locally executed run's results,
`SCOPE_RECON_PROMOTE` to promote or trigger. All three can be granted to a
workspace API client, so every command works unattended.

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

Points that decide whether it works:

- **`table:` beats `query:` when you can use it.** With `table:` the tool
  resolves the columns for you and you can narrow with `columns:`,
  `exclude_columns:` and `where:`. Reach for `query:` only when the comparison
  genuinely needs SQL.
- **Key columns drive everything.** Bisection orders and range-filters on them,
  so they must be unique and, ideally, indexed. `check-config --db` suggests one
  and warns if yours is not indexed.
- **Modes.** `row_count` compares counts only (fastest, misses modified values);
  `row_checksum` compares counts and a checksum of every column (the default,
  catches any difference); `aggregate` compares grouped measures like `SUM` and
  `COUNT` with a tolerance, and drills down through a `group_columns` hierarchy.
  `full` is an accepted legacy spelling of `row_checksum`; write `row_checksum`.
- **Column names differing only in case match automatically.** For genuinely
  different names use `column_mapping`.
- **Keep credentials out of the suite.** Put them in a git-ignored
  `.connections.yaml` (auto-discovered, or passed with `--connections`) keyed by
  the same connection names. This is also what lets the same suite run locally
  and in the workspace, where the names bind to integrations instead.

The exhaustive field list is the published schema, at a stable versioned URL:

- [Configuration reference](https://schemas.synq.io/synq-recon/v1/config.html) —
  every field, type, constraint and default, rendered.
- [`config.schema.json`](https://schemas.synq.io/synq-recon/v1/config.schema.json)
  — the machine-readable form. Point your editor at it for completion and
  validation:

```yaml
# yaml-language-server: $schema=https://schemas.synq.io/synq-recon/v1/config.schema.json
```

One field there is not yours to set: `motherduck_account` appears under the
DuckDB connection because the loader populates it internally. Write `database:`
with the MotherDuck account name, and pass `motherduck_token`.

### Avoiding false differences

Comparing two live systems is a moving target, and most "the data is wrong"
findings are really a comparison window problem. Reach for these first.

| Symptom | Use | What it does |
|---|---|---|
| Target lags the source; the tail looks "missing" | `cutoff:` | Derives a watermark from the data on each side, combines them (`min` by default — the point both sides have certainly reached), optionally truncates and offsets it, and filters both sides to at-or-below it. |
| Only the recent window matters | `window:` | Restricts the comparison to a lookback period. |
| Queries need a date or an id boundary | `variables:` | Resolved once, interpolated into both sides, recorded in the audit log. Override per run with `--var key=value`. |
| Comparing against a point-in-time snapshot | `as_of:` | Time-travel query on platforms that support it. |

---

## 5. Reading the output

**Pick your format explicitly.** `-o` defaults to `table` for a human terminal
and to `toon` when an AI-agent environment marker is present — so as an agent
you will get `toon` unless you say otherwise. Anything parsing output must pass
`-o json`.

**`run`, `run-check` and `run-drill` render only two shapes:** `-o json`, and a
text report for every other value. `--jq`, `--columns`, `--no-headers` and
`--wide` do not apply to them; pipe their `-o json` through `jq` yourself. The
workspace commands (`suite`, `deployment`, `runs`, `audit-logs`, `connections`,
`auth`) honour all six formats and all four flags.

**`run --auto-drill -o json` is not a single JSON document.** It emits the
quick-check document, then a plain-text banner, then one drill document per
drilled reconciliation. To parse the results, run the two stages separately —
`run-check -o json` then `run-drill -o json` — each of which is one valid
document.

```bash
# names that differ
synq-recon run-check suite.yaml -o json | jq -r '.results[] | select(.match == false) | .name'

# key ranges where the difference lives
synq-recon run-drill suite.yaml --include orders-daily -o json \
  | jq -r '.mismatch_leaves[] | "\(.segment.min_key) .. \(.segment.max_key)"'

# ready-to-run SQL for one difference, both sides
synq-recon run-drill suite.yaml --include orders-daily -o json \
  | jq -r '.investigation_queries[0] | .source_query, .target_query'
```

**Logs go to stderr, results to stdout.** Redirect with `2>/dev/null`, never
`2>&1`, when piping `-o json`.

**Exit codes.** Locally executed commands: `0` everything matched, `1`
differences were found *or* the command failed. For `run-remote --wait` and
`trigger --wait` the codes are data-driven and finer: `0` passed, `1` a
`--fail-on` condition was met (default `mismatched,failed`), `2` the run itself
failed. A run can succeed and still report a mismatch — that is the normal case.
`--fail-on=passed` inverts the test for a "these should differ" canary.

**Audit logs.** `--audit-log <path>` writes the full record of a run — every
query, timing, count, checksum and mismatch leaf — as JSON. Pass a directory
(trailing `/`) for an auto-named file. Its shape is the published AuditLog
schema — [rendered](https://schemas.synq.io/synq-recon/v1/audit-log.html), or
[`audit-log.schema.json`](https://schemas.synq.io/synq-recon/v1/audit-log.schema.json)
to validate against.

Useful paths, using the local file's casing:

```bash
jq -r '.reconciliations[].reconciliation.name' audit.json
jq -r '.reconciliations[].stages[].quick_check_result? | select(.) | "\(.source_count) vs \(.target_count)"' audit.json
jq -r '.reconciliations[].stages[].bisection_result?.mismatch_leaves[]?.segment | "\(.min_key)..\(.max_key)"' audit.json
```

Each mismatch leaf also carries a `drill_stop_reason` saying why drilling stopped
there, `diff_queries` with ready-to-run SQL for both sides, and every
`mismatch_types` that applies — so a segment differing in both size and content
reports two:

| Value | Meaning |
|---|---|
| `SEGMENT_MISMATCH_TYPE_MISSING_IN_TARGET` | Rows on the source side, none on the target — a real gap. |
| `SEGMENT_MISMATCH_TYPE_MISSING_IN_SOURCE` | Rows on the target side, none on the source — usually an orphan. |
| `SEGMENT_MISMATCH_TYPE_COUNT_MISMATCH` | Both sides have rows, but not the same number. |
| `SEGMENT_MISMATCH_TYPE_DATA_MISMATCH` | Both sides have rows and the checksums disagree — a value changed. |

Count direction alone does not classify a difference: a target with one row *more*
can still be missing a live row and carrying two orphans. Read the types.

Two traps in the same file:

> **Casing.** The local `--audit-log` file is snake_case (`bisection_result`,
> `mismatch_leaves`). The same log fetched from the workspace with
> `audit-logs get <invocation-id> -o json` is camelCase (`bisectionResult`,
> `mismatchLeaves`). A `jq` path written for one source silently returns `null`
> against the other.

> **Counts are strings.** Row counts and checksums are 64-bit integers, which
> JSON encodes as quoted strings in the audit log (`"source_count": "10"`) —
> unlike `run-check -o json`, where they are numbers. Compare with `tonumber`.

---

## 6. What each command costs

Reconciliation runs real queries against real warehouses, and on a
consumption-priced warehouse those queries cost money. Know which commands spend
before you put one in a loop.

| Command | Warehouse cost |
|---|---|
| `check-config` | None. Never connects. |
| `check-config --db` | One planner call per query (`LIMIT 0`, no scan) plus a table-metadata sweep. |
| `run-check` | One aggregate query per side. Scans the compared columns once. |
| `run-drill`, `run --auto-drill` | One bucketed query per bisection level per side. Cheap on mostly-identical data, expensive when most rows differ. |
| `recheck`, `drill-deeper` | Same as the stage they replay, but scoped to what the previous run left open — usually much cheaper than starting over. |
| `upload-config`, `promote`, `suite …`, `deployment …`, `runs …`, `audit-logs …` | None. Workspace API only. |
| `run-remote`, `trigger` | The run's cost, spent by the backend against workspace integrations. |

Two things worth knowing specifically:

**`check-config --db`'s table analysis can scale with warehouse size, not suite
size.** On platforms with no table-scoped metadata API — BigQuery in particular —
enumerating table metadata walks the datasets rather than jumping straight to
the tables your suite names. On a large warehouse that is slow and not free.
This is why the analysis is confined to the interactive `check-config --db` and
does not run before every reconciliation.

**Gate a large run before it happens.** `--max-table-rows` and
`--max-table-bytes` make `run`, `run-check` and `run-drill` estimate each
reconciliation's scan first — a dry run or `EXPLAIN`, not a scan — and warn when
an estimate exceeds the threshold. Both default to `0` (off) so automated runs
incur no extra queries. BigQuery and Snowflake report bytes; ClickHouse and
PostgreSQL report planner rows; DuckDB, Athena and Databricks advertise no
estimate support, so a gated run there simply emits no warnings.

**Keep a local run local.** With a stored credential present, a locally executed
run reports its results to Coalesce Quality so they appear in the workspace
alongside backend runs — even when every database in the suite is local. It says
so at `INFO`, naming the endpoint. Pass `--no-report` (or set `RECON_NO_REPORT`)
to resolve no credential and open no connection at all.

---

## 7. Investigating a finished run

`recheck` and `drill-deeper` take a finished run instead of a suite — either a
local audit-log file or, for a run stored in the workspace, its invocation id.

```bash
# Did the difference go away? (e.g. after a backfill)
synq-recon recheck audit.json --connections .connections.yaml

# Narrow every still-open segment to 100-row ranges
synq-recon drill-deeper audit.json --connections .connections.yaml --threshold 100

# Break each divergent aggregate group down by another column
synq-recon drill-deeper audit.json --add-group-column region
```

Four things govern how they behave:

- **Queries are replayed, not re-derived.** The audit log holds each query after
  variable interpolation and cutoff resolution, so a re-check compares the same
  window the original run did — which is what makes "did the gap move?" a
  meaningful question. It also means a replay will not pick up an edited query
  or variable until you pass `--reresolve`. `--reresolve` is required for an
  `as_of` snapshot, which can otherwise never turn green.
- **Only what was left open resumes.** `drill-deeper` picks up the segments the
  previous run stopped at on its row threshold or depth limit; `--depth` counts
  from the depth they already reached, so it means "this many more levels".
  Segments that could not be split further, and aggregate groups present on only
  one side, are reported and skipped rather than silently dropped. An aggregate
  drill already visits every configured group column, so resuming one needs at
  least one `--add-group-column`.
- **`recheck` re-runs only the reconciliations that did not pass.** `--all`
  re-runs every one.
- **Credentials never come from an audit log** — it records connection *names*
  only. Pass `--connections`, exactly as for a normal run.

Add `--remote` to either command to hand the replay to the backend instead,
running it against workspace integrations. `--remote` needs a stored run's
invocation id (a local file has nothing server-side to reference) and accepts
`--include` but not `--exclude`.

---

## 8. Command reference

`synq-recon <command> --help` is authoritative. This is the map.

### Local

| Command | What it does |
|---|---|
| `check-config <file>` | Validate a suite. `--db` also connects, validates every query, and analyses tables. |
| `run-check <file>` | Stage 1: counts and checksums. |
| `run-drill <file>` | Stage 2: bisect to locate differences. `--depth`, `--threshold`. |
| `run <file>` | Stage 1, then stage 2 on whatever mismatched with `--auto-drill`. |
| `recheck <run>` | Re-execute a finished run's queries and report what changed. `--all`, `--drill`, `--reresolve`. |
| `drill-deeper <run>` | Continue a finished run's drill. `--threshold`, `--depth`, `--add-group-column`. |
| `dump-suite <file>` | Print the parsed suite as protojson. Debugging aid. |

### Workspace

| Command | What it does |
|---|---|
| `auth login` / `logout` / `status` / `token` / `whoami` | Browser login and credential inspection. `--region` picks the deployment; `--auth-profile` picks which credential profile to read or write; `--isolated` stores a credential for `synq-recon` alone rather than sharing it with the other Coalesce Quality CLIs. |
| `upload-config <file>` | Save a suite to the workspace (Development). `--change-summary`. |
| `suite list` / `get` / `yaml` / `versions` / `delete` / `bootstrap` | Manage stored suites. `yaml` renders one back to editable YAML; `bootstrap` prints a skeleton. `list` takes `--connection`, `--include-adhoc`, `--limit`. |
| `connections remote list` / `bootstrap` | Inspect workspace integrations; generate a matching `.connections.yaml`. |
| `run-remote <suite-id>` | Ad-hoc backend run. `--drill`, `--map`, `--execution-timeout`, `--invocation-id`, `--wait`, `--fail-on`, `--wait-timeout`, `--poll-interval`. |
| `promote <suite-id>` | Publish to Production. `--schedule` (cron) or `--ical` (RFC 5545) with `--timezone` and optional `--dtstart`, plus `--triggerable-by-api`, `--drill`, `--execution-timeout`, `--map`, `--annotation`, `--clear-schedule`, `--deployment-id`, `--change-summary`. |
| `trigger <suite-id>` | Run a promoted deployment on demand. `--drill`, `--execution-timeout`, `--wait`, `--fail-on`, `--deployment-id`. |
| `unpromote <suite-id>` | Deactivate a deployment; history is kept. `--reason`. |
| `deployment list` / `get` / `history` / `update` / `pause` / `resume` / `set-annotations` | Inspect and edit deployments in place. `update` takes the same schedule and run-setting flags as `promote`, plus `--clear`; `pause` takes `--until`. |
| `runs list` / `cancel` | Inspect and cancel run state. `list` filters on `--status`, `--trigger`, `--suite`, `--deployment`, `--actor`, `--limit`. |
| `audit-logs list` / `get <invocation-id>` | Inspect stored run results. `list` filters on `--status`, `--suite`, `--limit`. |

**Deployment edits preserve what you omit.** `promote` on a re-promote, and
`deployment update` always, change only the settings you actually pass — so
refreshing a suite snapshot never silently unschedules the deployment or
disables API triggers. Removing a schedule is therefore explicit:
`deployment update --clear` or `promote --clear-schedule`. A *fresh* promote
applies defaults instead: no schedule, not triggerable, drill on.

**A deployment's id is part of every reconciliation's asset path**, so it is
worth keeping stable — rebuilding a deployment from scratch under a new id
re-homes its checks and drops their history. Re-promoting the same suite reuses
its id automatically; `promote --deployment-id <id>` pins one explicitly when
you are rebuilding.

### Flags accepted by every command

| Flag | Notes |
|---|---|
| `-o, --output` | `table`, `json`, `yaml`, `toon`, `tsv`, `wide`. See [Reading the output](#5-reading-the-output). |
| `--jq`, `--columns`, `--no-headers`, `--wide` | Shape structured output. Not honoured by `run`/`run-check`/`run-drill`. |
| `-v, --verbose` | Verbose logging, to stderr. |
| `--include`, `--exclude` | Select reconciliations by name; repeatable. Default is all. |
| `--var key=value` | Set or override a template variable; repeatable. |
| `--connections` | Connections file. Auto-discovers `.connections.yaml` / `connections.yaml` in the working directory. |
| `--dbt-profiles` | Resolve connections from a dbt `profiles.yml` as a fallback. |
| `-e, --environment`, `--env-file` | Apply a named set of overrides at load time. **Local only** — the workspace does not apply them. |
| `--timeout` | Per-query timeout for locally executed commands, default `5m`. Not the server-side run budget — that is `--execution-timeout`. |
| `--concurrency` | Reconciliations to run in parallel, default `1`. |
| `--max-table-rows`, `--max-table-bytes` | Pre-run scan estimate gate; `0` = off. |
| `--audit-log` | Write the run's audit log JSON to a file, or to a directory for an auto-named one. |
| `--no-report` | Keep the run local (or `RECON_NO_REPORT`). |
| `--actor-email` | Attribute write operations to this address (or `RECON_ACTOR_EMAIL`). |
| `--client-id`, `--client-secret` | Client credentials, overriding environment and YAML. |
| `--region`, `--endpoint` | Which deployment to talk to; see § 3. `--region` tab-completes. |
| `-y, --yes`, `--force` | Skip confirmation prompts; `--force` also bypasses safety checks. |

---

## 9. Worked example

Runnable end to end against the DuckDB fixtures shipped in this repository — no
warehouse, no credentials, no network. The suite deliberately contains a
difference: one missing order and one with a wrong amount.

```bash
cd synq-recon
go build -o synq-recon ./cmd/synq-recon      # needs CGO for DuckDB
```

**1. Validate.**

```bash
./synq-recon check-config examples/ecommerce.yaml
# Configuration check passed!
```

**2. Compare.**

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

Exit code 1 — differences found, as intended.

**3. Locate them, keeping the audit log.**

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

Order 1005 is missing from the target; order 1010 exists on both sides but its
checksum differs, so a column value changed. Two rows out of ten needed looking
at — that is the whole point of the bisection.

**4. Get the SQL that shows the actual rows.**

```bash
./synq-recon run-drill examples/ecommerce.yaml --include ecommerce-orders \
  --no-report -o json 2>/dev/null \
  | jq -r '.investigation_queries[] | .source_query, .target_query, "--"'
```

Run those against the two connections to see the differing rows themselves.

**5. Re-check after a fix.** The example's connection is defined in the suite,
so replaying it needs a connections file naming it:

```bash
printf 'connections:\n  test-db:\n    duckdb:\n      database: ":memory:"\n' > /tmp/conn.yaml
./synq-recon recheck /tmp/orders.json --connections /tmp/conn.yaml --no-report
```

```
RECONCILIATION    BEFORE       AFTER        CHANGE
----------------  -----------  -----------  ------------------------------------------
ecommerce-orders  mismatched   mismatched   still mismatched (row gap unchanged at -1)
```

Nothing changed because nothing was fixed — but that line is the shape of the
answer you are looking for after a real remediation.

**6. Try the aggregate mode** on the same suite, which localises a difference
by group rather than by key range:

```bash
./synq-recon run examples/ecommerce.yaml --include inventory-reconciliation \
  --auto-drill --no-report
```

More scenarios live in [`examples/`](examples/), one per business case.
`./examples/test-all-examples.sh` runs every one.

---

## 10. When something goes wrong

| What you see | What it means |
|---|---|
| `Validation failed: no connections defined` from offline `check-config` | The suite's `connection:` fields are workspace integration ids, not local definitions. Pass `--connections <file>` to validate the wiring, add `--db` to connect. |
| Every query fails `check-config --db` with "table does not exist" | `--db` does not run the suite's `setup:` SQL. Expected for a suite whose tables are created by setup. |
| `no connections available to replay run …` | `recheck` / `drill-deeper` need `--connections`: an audit log records connection names, never credentials. |
| `accepts 1 arg(s), received 2` | A reconciliation name was passed positionally. Use `--include <name>`. |
| A drill produces thousands of leaves and takes minutes | The data is not mostly-identical. Localise with an aggregate comparison first — see [Never do these](#2-never-do-these). |
| A warning that the stored credential is missing a scope | The command still works if the scope it needs is present. A credential without the reporting scope only means a local run's results are not reported; the comparison is unaffected. |
| `deployment is not active; re-promote to modify` | The deployment was unpromoted. Re-promote before changing or tearing it down. |
| `N connection(s) could not be bound to an integration` | A suite connection has no matching workspace integration, or the integration is not permitted for reconciliation. Check names with `connections remote list`, or bind explicitly with `--map name=integration_id`. |
| `-o json` output will not parse | Either logs were merged into stdout (`2>&1`), or it was `run --auto-drill`, which emits more than one document. See [Reading the output](#5-reading-the-output). |
| A promoted suite still runs the old comparison | A deployment is a snapshot. Re-promote after editing the suite. |
| `type: duckdb` fails inside the Docker image | That image was built without CGO. Current images support DuckDB — pull `:latest`, or use a locally built binary. |
