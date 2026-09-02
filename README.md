# SAP HANA Query Optimizer — An Evidence-Based Study

What does SAP HANA's query optimizer actually do as a table grows from a
handful of rows to a million? This repository is an attempt to find out by
measuring rather than assuming — the same eight queries, run at four scales,
with every execution plan captured and kept as evidence.

**Environment** — SAP HANA Cloud, SAP HANA Database Explorer, HEX execution
engine, all tables column-store.

---

## What was actually tested

A small retail schema — customers, products, orders, order lines — was built
and populated at four sizes: a 7-row baseline, then 10,000, 100,000, and
1,000,000 rows in the largest table. The same eight queries ran at every
tier, and their execution plans were captured and compared.

Three other things were tested alongside the scaling itself:

- **What it costs to override the optimizer.** A join was forced into a
  nested loop using a hint, at each scale, and compared against the plan the
  optimizer chose on its own.
- **What happens when reads and writes overlap.** Whether a read gets blocked
  by an open write, and whether an analytical query stays fast while a large
  concurrent insert is running.
- **Whether workload governance actually works.** Whether a workload class,
  once configured, genuinely limits a query's resource use — checked against
  the database's own admission statistics, not just against a timer.

---

## Findings, in brief

**The same join gets a different algorithm depending on where it sits in the
query.** An identical join condition, on identical tables, at identical row
counts, was given an index join when it stood alone and a hash join when it
was part of a longer chain. This held at every scale tested. Table size alone
does not decide the plan — the surrounding query does.

**Overriding the optimizer gets more expensive as data grows, and not
proportionally.** Forcing a nested loop join cost roughly 46 times more than
the optimizer's own plan at ten thousand rows, and roughly 3,352 times more
at one million. The penalty for a wrong plan widens faster than the data
does.

**Reads are not blocked by writes.** A session reading a row was never made
to wait for a concurrent, uncommitted write to the same row, and never saw
the uncommitted value either. Both guarantees held at once.

**A full aggregation stayed fast during a large concurrent write.** An
aggregation over a million-row table finished in milliseconds while two
million rows were being inserted into the same table at the same time.

**Workload classes only govern once mapped to something the session actually
presents.** A class that looked fully configured was found, on inspection of
the database's own admission counters, to be governing nothing — the mapping
had been made on a session attribute the connection never set. Once
corrected, the same class measurably slowed a governed query relative to an
ungoverned one.

Full detail, discussion, and the limitations of each finding are worked
through in the accompanying report.

---

## Repository structure

| Path | Contents |
|---|---|
| `sql/` | Schema, data generation, the eight queries, hint syntax, workload class setup |
| `plans/10K/`, `plans/100K/`, `plans/1M/` | Captured execution plans at each scale tier |
| `plans/Baseline_query_plans/` | Plans at the smallest (7-row) tier |
| `plans/Plans_Reference/` | Catalog query output used to confirm correct hint names |
| `screenshots/` | Console captures for the concurrency and workload governance tests |
| `scaling-phase/` | Working files from building up each tier |
| `archive/` | Earlier drafts and exploratory work, kept for reference rather than deleted |

Plan files are named by query and purpose — for example `Q4_multi_join.csv`
for the optimizer's own plan, and `Q4_nestedloop_hint.csv` for the same query
with the nested loop forced.

---

## A note on the process

Two things went wrong during this project and are recorded rather than
quietly fixed: a batch of plans was captured before a data reload had
actually finished, producing results that looked plausible but described the
wrong tier; and a workload mapping looked correctly configured while
governing nothing at all, caught only by checking the database's own
admission statistics rather than trusting the timing alone. Both are kept in
the evidence trail, because working out what had gone wrong turned out to be
as informative as the results themselves.

---

## Sanitization

Plan exports originally contained the database instance ID, schema name, and
connection ID. Every file in `plans/` has been processed with
[`sanitize_plan_csv.py`](sanitize_plan_csv.py), which removes these three
fields and leaves everything else — operators, costs, row counts,
timestamps — unchanged.

```bash
python sanitize_plan_csv.py <file1.csv> [file2.csv ...]
```

---

## Reproducing this

1. Provision a HANA Cloud instance and open Database Explorer.
2. Run the schema and generation scripts in `sql/` for whichever tier you
   want to reproduce.
3. Capture a plan with `EXPLAIN PLAN SET STATEMENT_NAME = 'Qn' FOR <query>;`,
   then read it back from `SYS.EXPLAIN_PLAN_TABLE`.
4. Compare the result against the matching file in `plans/`. Operator
   *shapes* should match; absolute costs will vary with instance sizing.

---

## Scope

- Plan costs are the optimizer's own estimates, not measured wall-clock time,
  except where a result was explicitly timed (the concurrency and workload
  governance tests were both measured directly).
- The dataset is synthetic and generated with even distributions, so nothing
  here speaks to how the optimizer behaves under real-world data skew.
- Everything ran on a single-node instance; the findings do not extend to a
  distributed deployment without further testing.
