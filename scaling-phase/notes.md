# Project Lab Notes — HTAP-Optimized Retail Order Fulfillment Engine

**Subject 1:** Database Theory & Management — *Stress-Testing a Retail Logistics Database under Mixed Transactional-Analytical Load: Optimizer Behavior, Concurrency, and Workload Throttling in SAP HANA Cloud*

**Subject 2:** SAP Business Technology Platform — *HTAP-Optimized Retail Order Fulfillment Engine on SAP BTP: Cross-Module SD/MM/FI Integration for High-Concurrency Retail Events*

**Environment:** SAP HANA Cloud instance `HSF_DB`, university subaccount "Master of SAP Engineering & Analytics"

---

## Access Requests Log

Running list of privileges/roles requested from professor. Update as new blockers appear, batch into one email where possible.

| # | Date requested | What was requested | Status | Notes |
|---|---|---|---|---|
| 1 | [fill in] | `WORKLOAD ADMIN` system privilege on `HSF_DB` (needed for `CREATE WORKLOAD CLASS`) | ⏳ Pending | Error code 258, insufficient privilege, hit during Phase 1 setup verification |
| 2 | [fill in] | Permission to save SQL Analyzer Plan Files (diagnostic file write access) | ⏳ Pending | "Authentication failed. Password required" when using Generate SQL Analyzer Plan File on Q1. Needed later for hint-benchmarking (Phase 2, Q4/Q5) — not urgent yet, Explain Plan works fine for now |
| 3 | | | | |

**Draft email (v2):**
> Subject: HSF_DB — Additional Privileges Needed for Coursework Project
>
> Hi [Professor],
>
> I'm working on my HANA project using the HSF_DB instance and have successfully created my base schema (4 tables) and started running analytical queries. I've run into two privilege gaps so far:
>
> 1. WORKLOAD ADMIN system privilege — needed to run CREATE WORKLOAD CLASS, which is required for the workload management section of my project (error code 258, insufficient privilege).
> 2. Permission to save SQL Analyzer Plan Files — I get "Authentication failed, password required" when trying to generate a full performance trace via Database Explorer. I'll need this for a query hint-comparison experiment later in the project.
>
> Could these be granted to my database user? Happy to provide more detail if needed.
>
> Thanks,
> [Your name]

---

## Running Log (chronological — one entry per session)

> Format: `[Date] — What I did — What happened — What's next`

- **[Date]** — Reviewed BTP Role Collections in university environment. Currently have Viewer-level access only (BAS Developer, HANA Cloud Viewer, Data Publisher Viewer, Subaccount Viewer). Flagged need for Administrator + Space Developer roles, plus HANA-level `WORKLOAD ADMIN` privilege, separately.
- **[Date]** — Confirmed a live SAP HANA Cloud instance (`HSF_DB`) already provisioned in the university subaccount. Status: Created. Subscriptions active for SAP HANA Cloud tools and SAP Business Application Studio.
- **[Date]** — Connected to `HSF_DB` via SAP HANA Database Explorer. Ran access verification test (`CREATE TABLE ACCESS_TEST...`) — succeeded. Confirmed can create real objects in this database.
- **[Date]** — Attempted `CREATE WORKLOAD CLASS` on `HSF_DB` — failed with error 258 (insufficient privilege). Confirms missing `WORKLOAD ADMIN`. Logged as Access Request #1.
- **[Date]** — Phase 1 complete: created 4-table logistics schema (Customers, Products, SalesOrders, OrderItems) as COLUMN tables with PK/FK constraints in `HSF_DB`. Verified via `SYS.TABLES`.
- **[Date]** — Seeded schema with initial hand-crafted dataset (5 customers, 5 products, 6 orders, 7 order items) to validate relational integrity before synthetic bulk seeding at 10K/100K/1M scale. Row counts confirmed. Cross-table JOIN query returned correct, readable results — relational integrity validated.
- **[Date]** — Started Phase 2 (Path B: validate queries on small dataset before scaling). Ran Query 1 (single-table aggregation). Plan captured via Explain Plan, exported as Q1_plan.csv.
- **[Date]** — Q2 (filtered single-table scan, WHERE StockQty < 300) executed. Returned 1 row (Hydraulic Pump B2, qty 120) — correctly excluded Control Valve D4 (qty exactly 300, boundary condition proves filter precision). Plan exported as Q2_plan.csv.
- **[Date]** — Attempted "Generate SQL Analyzer Plan File" on Q1 — hit "Authentication failed, password required" trying to save diagnostic .plv file. Logged as Access Request #2. Reverted to Explain Plan (sufficient for structural analysis at this stage).
- **[Date]** — Q3 (2-table JOIN, SalesOrders→Customers) executed, 6 rows. **Key finding:** optimizer selected INDEX JOIN (many-to-one on CustomerID, a primary key) rather than hash/nested-loop join — automatic recognition of PK relationship. Plan exported as Q3_plan.csv.
- **[Date]** — Q4 (4-table JOIN: OrderItems→SalesOrders→Customers→Products) executed, 7 rows. **Key finding:** optimizer chose OrderItems (largest table, 7 rows) as the driving table rather than the smallest — because OrderItems holds FKs to all other tables, enabling direct index lookups at each step. Confirmed via subtree cost: OrderItems alone = 2.1e-8, cheapest single step in the plan. Three chained INDEX JOINs, no hash/nested-loop triggered (all joins on primary keys). Plan exported as Q4_plan.csv.
- **[Date]** — Q5 (JOIN + aggregation: revenue per category) executed, 3 rows. **Key finding:** optimizer joined OrderItems→Products BEFORE aggregating by Category, not after — judged cheapest at current row counts. This decision is scale-dependent and expected to be re-evaluated once seeded to 1M rows (ties directly to the optimizer-shift experiment planned for Phase 2 continuation). Result values cross-checked manually against seed data — confirmed correct (Electronics: 32 units, €3,952.28). Plan exported as Q5_plan.csv.
- **[Date]** — **Phase 2 baseline complete.** All 5 analytical queries executed, plans captured, and analyzed on small hand-seeded dataset. Consistent finding across Q3–Q5: HANA's optimizer reliably chooses INDEX JOIN over hash/nested-loop whenever a primary-key relationship exists — meaning the hint-comparison experiment (USE_HASH_JOIN vs USE_NESTED_LOOP_JOIN) will need either scaled data (10K/100K/1M) or a non-key join condition to produce a genuinely contested decision. Comparison table fully updated in query-comparison.xlsx.
- **[Date]** — Reproduced both of professor's named optimizer rewrite examples on our own schema: (1) repeated correlated subquery — found NOT deduplicated when wrapped differently (once direct, once inside CASE) — two independent computation branches instead of one shared/reused branch, with the two resulting LEFT OUTER joins using different algorithms (INDEX JOIN vs HASH JOIN); (2) EXISTS subquery — confirmed correctly rewritten into a single INDEX JOIN (SEMI) operation, exactly as course material describes.
- **[Date]** — Hit TRUNCATE TABLE error [7] ("feature not supported: truncate on tables with foreign key constraints") when clearing small dataset ahead of scaling. Switched to DELETE (child-to-parent order: OrderItems → SalesOrders → Products → Customers), which respects FK constraints row-by-row.
- **[Date]** — Hit invalid column name error on OrderItems INSERT. Diagnosed via SYS.TABLE_COLUMNS catalog query and Database Explorer's Catalog browser: the intended primary key column had been created as "ORDERITEMS" instead of "ORDERITEMID" (typo in original Phase 1 schema script). Fixed via RENAME COLUMN. Good practical example of catalog-based schema diagnosis.
- **[Date]** — **10K scale tier successfully seeded**: 1,000 Customers, 200 Products, 4,000 SalesOrders, 10,000 OrderItems (verified row counts match target exactly). Used SERIES_GENERATE_INTEGER-based generators with controlled category/region cardinality (4 values each), MOD()-based FK cycling to guarantee referential integrity by construction, and follow-up UPDATE statements to back-fill LineTotal/TotalValue for arithmetic consistency.
- **[Date]** — **Analyzed all 6 scaling-phase execution plans (4 generation INSERTs + 2 correction UPDATEs).** Two standout findings:
  1. **MATERIALIZE pattern**: appears in every generator plan that uses RAND() (Products, Customers, OrderItems) and is absent from the one fully-deterministic generator (SalesOrders) — confirms MATERIALIZE exists specifically to lock in random values per row before reuse.
  2. **Table function row-count estimate is a fixed default (10,000)** regardless of actual requested rows (200, 1000, 4000, or 10000 all showed the same TABLE_SIZE/OUTPUT_SIZE=10000 for the SERIES_GENERATE_INTEGER step) — because the real count is a runtime parameter invisible at plan time. A genuine limitation of cost-based estimation, worth noting as a "rule-based fallback within a cost-based system" moment.
  3. **First natural HASH JOIN observed** (UPDATE OrderItems.LineTotal) — every prior join (Q3–Q5) chose INDEX JOIN, even on identical primary-key conditions. Here, because the UPDATE touches ALL 10,000 rows (non-selective), HANA built one hash table from the smaller side (Products, 200 rows) instead of doing 10,000 individual index lookups. Direct, unforced evidence of why hash joins exist.
  4. **CONFIRMS the Q5 prediction** (UPDATE SalesOrders.TotalValue) — at 10,000 rows, the optimizer now aggregates OrderItems by OrderID BEFORE joining to SalesOrders, the OPPOSITE of Q5's small-scale behavior (join first, then aggregate at 7 rows). Named technique confirmed in plan: `ENUM_BY: AGGR_THRU_JOIN`. **This is the strongest empirical finding in the project so far** — two real, comparable plans at different scales showing opposite optimizer strategies.
  
  Full breakdown in `query-comparison.xlsx`, sheet "Scaling & Generation Plans."

---

## Query Comparison Table (Phase 2 — Optimizer & Execution Plan Analysis)

**Moved to `query-comparison.xlsx`** — this is now the single source of truth for query-by-query comparison (easier to sort/filter/chart than markdown). Do not duplicate this table here — update the Excel file directly.

Raw plan data (CSV exports from Database Explorer's Explain Plan) are archived untouched in `/03-optimizer-plans/raw-csv/`:
- `Q1_plan.csv` ✅ downloaded
- `Q2_plan.csv` ✅ downloaded
- `Q3_plan.csv` ✅ downloaded
- `Q4_plan.csv` ✅ downloaded
- `Q5_plan.csv` — confirm downloaded (last query, verify before moving on)

**Status: Phase 2 baseline (5 queries at small scale) is COMPLETE.** All rows filled in `query-comparison.xlsx`. Next: reproduce professor's 2 named rewrite examples (CTE dedup, EXISTS→JOIN), then scale to 10K/100K/1M and re-run these same 5 queries to observe optimizer-shift behavior.

Workflow: run query → export/copy plan as CSV → file in raw-csv/ → hand-pick the key values into one row of `query-comparison.xlsx`.

---

## Hint Benchmarking (USE_HASH_JOIN vs USE_NESTED_LOOP_JOIN)

To be filled in once we reach the join-heavy queries (Q4/Q5) at scale. Use "Generate SQL Analyzer Plan File" for real timing/memory numbers here, not just Explain Plan.

| Hint Used | Query | Execution Time | Memory Used | Notes |
|---|---|---|---|---|
| (none — optimizer default) | | | | |
| USE_HASH_JOIN | | | | |
| USE_NESTED_LOOP_JOIN | | | | |

---

## Optimizer Rewrite Examples (from professor's own lecture slides)

Reproduce his two named examples on our own schema — direct rubric alignment.

- [ ] **CTE dedup example** — before/after plan captured
- [ ] **EXISTS → JOIN unnesting example** — before/after plan captured

---

## Concurrency & Isolation Level Demos (Phase 3)

| Demo | Isolation Level Tested | What Happened | Screenshot |
|---|---|---|---|
| Dirty read | | | |
| Phantom read | | | |
| SELECT...FOR UPDATE lock | | | |
| Deadlock (wait-for-graph) | | | |

---

## HTAP Mixed Load Test (Phase 3)

- Tool used: (JMeter / k6 / other)
- Thread Group 1 (OLTP writes): ___% of traffic
- Thread Group 2 (OLAP reads): ___% of traffic
- Monitoring views checked: `M_EXPENSIVE_STATEMENTS`, `M_ACTIVE_STATEMENTS`, `M_CONNECTIONS`
- Findings:

---

## Workload Class Throttling (Phase 4) — BLOCKED on Access Request #1

- Before throttling — checkout response time under load:
- After WORKLOAD CLASS applied — checkout response time under load:
- Screenshot(s):

---

## PAL K-Means Clustering (Phase 5)

- Privilege check needed: (test `AFL__SYS_AFL_AFLPAL_EXECUTE` or similar — add to Access Request Log if blocked)
- Clusters produced:
- Interpretation of customer segments:

---

## Distributed Systems Theory Chapter (closing chapter, Lecture 12 tie-in)

Professor's explicit question: *"How does this compare to SAP HANA in general and in the scale-out and HA (high-availability) setups?"*

- HANA scale-out/HA — architecture notes:
- Comparison point: Pinecone (AP-leaning, eventually consistent, vector-purpose-built)
- Comparison point: Supabase (Postgres — CP-leaning, single-primary + read replicas, not natively sharded)
- CAP theorem positioning of each:
- BASE properties discussion:
- 2PC / Spanner global ACID discussion:
- Conflict resolution (LWW / CRDTs) discussion:

---

## Subject 2 (BTP) — Build Log

- [ ] CAP Node.js project initialized in BAS
- [ ] OData V4 services exposing SalesOrders, Inventory, AnalyticsSummary
- [ ] Fiori Elements dashboard built
- [ ] SAP Build Process Automation — credit approval workflow
- [ ] XSUAA roles configured: StoreManager, WarehouseOperator, FinancialAnalyst
- [ ] MTA packaging + Cloud Foundry deployment
- [ ] **Reminder: include Sapphire 2026 / unified SAP Build consolidation paragraph in architecture chapter**

---

## Report-Ready Screenshot Index

Quick reference so nothing gets lost when writing the final report. Update the checkbox as each is captured.

- [x] Before/after BTP Role Collections screenshot
- [x] Instances & Subscriptions page (`HSF_DB` created)
- [x] Access verification test success (`ACCESS_TEST` table)
- [x] Workload class privilege error (code 258)
- [x] Schema creation success (4 tables, `SYS.TABLES` check)
- [x] Seed data row-count verification
- [x] Cross-table JOIN result (relational integrity proof)
- [x] Q1 execution plan
- [x] Q2 execution plan
- [x] Q3 execution plan
- [x] Q4 execution plan
- [x] Q5 execution plan
- [x] Professor's 2 named rewrite examples (CTE dedup, EXISTS→JOIN)
- [x] Data scaled to 10K rows (1,000 Customers, 200 Products, 4,000 SalesOrders, 10,000 OrderItems)
- [x] 6 scaling-phase plans analyzed (4 generation INSERTs + 2 correction UPDATEs) — see Scaling & Generation Plans sheet
- [ ] Data scaled to 100K rows
- [ ] Data scaled to 1M rows
- [ ] Q1–Q5 re-run at 100K/1M scale (further optimizer-shift evidence)
- [ ] Hint comparison results (USE_HASH_JOIN vs USE_NESTED_LOOP_JOIN)
- [ ] Concurrency/isolation demos
- [ ] HTAP load test monitoring views
- [ ] Workload throttling before/after
- [ ] PAL clustering output
- [ ] BTP CAP service running
- [ ] Fiori dashboard screenshot
- [ ] Live CF deployment URL
