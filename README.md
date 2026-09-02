# SAP HANA Query Optimizer — An Evidence-Based Study

An empirical study of how the SAP HANA Cloud query optimizer behaves as data
volume grows, and how the database protects itself when transactional and
analytical work compete for the same resources. This repository is the
evidence trail behind the submitted report; every figure quoted in the report
is backed by a file committed here.

**Environment** — SAP HANA Cloud (`HSF_DB`), schema `NSHARMA`, accessed via
SAP HANA Database Explorer, HEX execution engine, all tables COLUMN store.

---

## What this study covers

Eight queries (Q1–Q8) run at four scale tiers — baseline (7 rows), 10K, 100K,
and 1M — over a four-table order-to-cash schema (`Customers`, `Products`,
`SalesOrders`, `OrderItems`). Alongside the plan captures, the study also
covers:

- **Overriding the optimizer** — forcing a nested loop join with
  `HEX_NESTED_LOOP_JOIN` and measuring the cost penalty as data grows
- **Concurrency** — MVCC read behaviour during an open write transaction, and
  an analytical query running alongside a two-million-row concurrent insert
- **Workload governance** — creating a workload class, mapping it to a
  session, and verifying it actually throttles a query via
  `M_WORKLOAD_CLASS_STATISTICS`

Full findings, discussion and limitations are in the submitted report. This
README indexes the supporting evidence; it does not restate the analysis.

---

## Repository structure

| Path | Contents |
|---|---|
| `sql/` | Schema DDL, data generation scripts, the eight queries, hint syntax, workload class setup |
| `plans/10K/` | Query plans at the 10,000-row tier |
| `plans/100K/` | Query plans at the 100,000-row tier |
| `plans/1M/` | Query plans at the 1,000,000-row tier |
| `plans/Baseline_query_plans/` | Query plans at the 7-row baseline tier |
| `plans/Plans_Reference/` | `SYS.HINTS` catalog output — the reference behind the hint-naming findings |
| `screenshots/` | Console captures for the MVCC and concurrency tests, and workload class verification |
| `scaling-phase/` | Working files from the tier-by-tier scale-up |
| `archive/` | Superseded drafts and exploratory work, kept for reference |

Each plan file is named by query and purpose, e.g. `Q4_multi_join.csv` (the
optimizer's own plan) and `Q4_nestedloop_hint.csv` (the same query with the
nested loop hint forced). `Q8_selfjoin.csv` is present at every tier.

---

## Sanitization

Every plan export originally contained the HANA instance ID, schema name and
connection ID. All files in `plans/` have been run through
[`sanitize_plan_csv.py`](sanitize_plan_csv.py), which redacts these three
fields before the file is committed. Operator names, costs, cardinalities and
timestamps are untouched — only connection metadata is removed. Run the
script yourself against any new export before adding it:

```bash
python sanitize_plan_csv.py <file1.csv> [file2.csv ...]
```

---

## Key figures (as reported)

For quick cross-reference against the submitted report:

| Finding | Figure | Evidence |
|---|---|---|
| Same join, different algorithm depending on context | Q3 stays INDEX JOIN at every tier; Q4's equivalent join switches to HASH JOIN from 10K onward | `plans/10K/Q3_single_join.csv`, `plans/10K/Q4_multi_join.csv` (and 100K/1M equivalents) |
| Cost of forcing a nested loop join | 46× at 10K, 386× at 100K, 3,352× at 1M | `plans/*/Q4_nestedloop_hint.csv` vs `plans/*/Q4_multi_join.csv` |
| Non-blocking reads under MVCC | Session B reads the prior committed value while session A's write is open | `screenshots/` MVCC captures |
| Mixed transactional/analytical load | 28 ms aggregation while a 2M-row insert runs concurrently | `screenshots/` HTAP capture |
| Workload class governance | Governed query slows by ~5.7× once correctly mapped, confirmed via admit count | `screenshots/` workload governance capture |
| Correct hint syntax | `HEX_NESTED_LOOP_JOIN`, not the Oracle-style names first assumed | `plans/Plans_Reference/HANA_SYS_HINTS.csv` |

---

## Reproducing this

1. Provision a HANA Cloud instance and open Database Explorer.
2. Run the schema and generation scripts in `sql/` for the tier you want to
   reproduce.
3. Capture a plan with `EXPLAIN PLAN SET STATEMENT_NAME = 'Qn' FOR <query>;`
   then read `SYS.EXPLAIN_PLAN_TABLE`.
4. Compare against the corresponding file in `plans/`. Operator *shapes*
   should match; absolute costs will vary with instance sizing.

---

## Scope and honesty statement

- All costs in the plans are the optimizer's own estimates, not measured
  wall-clock time, except where the report explicitly states a timed result
  (the concurrency and workload governance figures were measured directly).
- Two configuration mistakes were made and corrected during this study — a
  set of plans captured before a data reload had finished, and a workload
  mapping that looked active but governed nothing. Both are documented in the
  report rather than silently fixed, since the diagnosis was itself a result.
- This repository supports the submitted report and is provided as a
  cross-reference; the report is the primary document.
