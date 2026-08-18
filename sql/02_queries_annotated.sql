/* ============================================================================
   02_QUERIES_ANNOTATED.SQL
   Seven queries of increasing complexity, each annotated with the plan that
   SAP HANA actually produced.
   ----------------------------------------------------------------------------
   Every "OBSERVED PLAN" block below is transcribed from the corresponding CSV
   in /plans, which was captured with:

       EXPLAIN PLAN SET STATEMENT_NAME = 'Qn' FOR <query>;
       SELECT * FROM SYS.EXPLAIN_PLAN_TABLE WHERE STATEMENT_NAME = 'Qn';

   Nothing in the annotations is inferred from documentation. Where a claim
   could not be confirmed from the plan, it is marked NOT PROVEN.

   Cost figures are the optimizer's SUBTREE_COST at the root operator. They are
   unitless estimates, not milliseconds. On a 23-row dataset they are useful
   only for RELATIVE comparison between these seven queries.
   ========================================================================= */


/* ############################################################################
   Q1 — SINGLE-TABLE AGGREGATION
   Business question: what is our inventory value, broken down by category?
   Plan: plans/Q1_aggregation.csv        Result: screenshots/Q1_aggregation.jpg
   ######################################################################### */

SELECT
    Category,
    COUNT(*)                 AS ProductCount,
    SUM(UnitPrice*StockQty)  AS TotalInventoryValue
FROM Products
GROUP BY Category
ORDER BY TotalInventoryValue DESC;

/*  OBSERVED PLAN                                    engine: HEX   cost: 1.35e-6
    ------------------------------------------------------------------------
    PROJECT
      ORDER BY   SUM(...) DESC
        AGGREGATION   GROUPING: CATEGORY
                      props: VALUE_ID GROUPING, PERFECT_HASH
          TABLE SCAN  PRODUCTS   (table 5 rows -> output 5 rows)

    OBSERVATIONS
    1. VALUE_ID GROUPING is the column store paying off. HANA does not group on
       the string 'Electronics'; it groups on the integer dictionary code for
       'Electronics'. Grouping is therefore integer comparison, not string
       comparison, regardless of how long the category names are.
    2. PERFECT_HASH means HANA proved the distinct group count is small enough
       to use a collision-free hash table — no spill, no rehash, no fallback.
    3. There is no separate "compute UnitPrice*StockQty" operator. The
       arithmetic is fused into the AGGREGATION node. HANA did not materialise
       an intermediate 5-row projection just to multiply two columns.
    4. Note the implicit TO_DECIMAL(...,20,2) and TO_DECIMAL(...,20,0) casts in
       OPERATOR_DETAILS. Multiplying DECIMAL(10,2) by INTEGER forces a widening
       cast that we never wrote. On a wide fact table this cast is a real cost;
       here it is free.
    5. ORDER BY sits ABOVE the aggregation, so it sorts 3 rows, not 5. Sorting
       after reduction is the cheap ordering and HANA chose it without hinting.

    BASELINE: 1.35e-6. Everything below is compared against this. */


/* ############################################################################
   Q2 — FILTERED SCAN  (predicate pushdown)
   Business question: which products need reordering?
   Plan: plans/Q2_filter_pushdown.csv   Result: screenshots/Q2_filter_pushdown.jpg
   ######################################################################### */

SELECT
    ProductID,
    ProductName,
    Category,
    StockQty,
    UnitPrice
FROM Products
WHERE StockQty < 300
ORDER BY StockQty ASC;

/*  OBSERVED PLAN                                    engine: HEX   cost: 8.93e-8
    ------------------------------------------------------------------------
    PROJECT
      ORDER BY   PRODUCTS.STOCKQTY ASC
        TABLE SCAN  PRODUCTS
                    FILTER CONDITION: PRODUCTS.STOCKQTY < 300
                    DETAIL: ([SCAN] PRODUCTS.STOCKQTY < 300)
                    (table 5 rows -> output 1 row)

    OBSERVATIONS
    1. THERE IS NO FILTER OPERATOR. The WHERE clause was pushed INTO the scan
       node. HANA never produces 5 rows and then discards 4 — it produces 1.
       This is the single most important line in the whole plan set, because
       every performance rule about "filter early" is visible right here as a
       structural property of the tree rather than as advice.
    2. TABLE_SIZE 5 vs OUTPUT_SIZE 1 quantifies the pushdown: 80% of rows were
       eliminated before any operator above the scan ever saw them.
    3. The [SCAN] tag inside DETAIL is the evaluation site. HANA is stating
       that the predicate is evaluated during the scan itself, not by a
       post-scan expression evaluator.
    4. COST COMPARISON — Q2 is 15x CHEAPER than Q1 (8.93e-8 vs 1.35e-6) despite
       reading the same table. The difference is entirely downstream volume:
       Q1's aggregation must consume 5 rows, Q2's sort consumes 1. Adding a
       WHERE clause made the query cheaper than the unfiltered aggregate — the
       opposite of the intuition that "more clauses = more work".

    CHEAPEST QUERY IN THE SET. */


/* ############################################################################
   Q3 — TWO-TABLE JOIN
   Business question: who placed which orders, and when?
   Plan: plans/Q3_single_join.csv        Result: screenshots/Q3_single_join.jpg
   ######################################################################### */

SELECT
    c.CustomerName,
    c.Region,
    so.OrderID,
    so.OrderDate,
    so.Status,
    so.TotalValue
FROM SalesOrders so
JOIN Customers c ON so.CustomerID = c.CustomerID
ORDER BY so.OrderDate;

/*  OBSERVED PLAN                                    engine: HEX   cost: 1.64e-6
    ------------------------------------------------------------------------
    PROJECT
      ORDER BY   SO.ORDERDATE ASC
        INDEX JOIN   MANY-TO-ONE  ON SO.CUSTOMERID = C.CUSTOMERID
                     probed table: CUSTOMERS   (5 rows -> 6 rows out)
          TABLE SCAN SALESORDERS  (6 rows -> 6 rows)

    OBSERVATIONS
    1. INDEX JOIN, not hash join and not nested loop. No hash table is built.
       HANA walks the SALESORDERS scan and probes the CUSTOMERS primary-key
       index once per row. On a PK-to-FK join this is the ideal shape.
    2. MANY-TO-ONE is a CORRECTNESS PROOF, not a guess. It is derived from
       fk_order_customer plus the PK on Customers: many orders, exactly one
       customer. Because HANA knows the right side cannot produce duplicates,
       it knows output cardinality equals left cardinality — hence OUTPUT_SIZE
       6, matching the 6 rows in SalesOrders, with no estimation error.
    3. DRIVING SIDE IS THE FACT TABLE. We wrote FROM SalesOrders JOIN Customers,
       and HANA also drove from SalesOrders — but not because we wrote it that
       way. Q4 below proves the textual order is ignored.
    4. Only one table is scanned. CUSTOMERS is never scanned; it is only probed.
       A plan with two TABLE SCAN nodes under a join would mean HANA had to
       materialise both sides — that is not what happened here.
    5. COST: 1.64e-6, only 1.2x Q1. Adding a whole second table cost almost
       nothing, because the join was answered by an index probe rather than a
       build-and-probe. */


/* ############################################################################
   Q4 — FOUR-TABLE JOIN  (the join-reordering experiment)
   Business question: what did each order actually contain?
   Plan: plans/Q4_multi_join.csv          Result: screenshots/Q4_multi_join.jpg
   ######################################################################### */

SELECT
    so.OrderID,
    c.CustomerName,
    p.ProductName,
    oi.Quantity,
    oi.LineTotal
FROM SalesOrders so
JOIN Customers  c  ON so.CustomerID = c.CustomerID
JOIN OrderItems oi ON so.OrderID    = oi.OrderID
JOIN Products   p  ON oi.ProductID  = p.ProductID
ORDER BY so.OrderID;

/*  OBSERVED PLAN                                    engine: HEX   cost: 3.56e-6
    ------------------------------------------------------------------------
    PROJECT
      ORDER BY   SO.ORDERID ASC
        INDEX JOIN  MANY-TO-ONE  OI.PRODUCTID = P.PRODUCTID     [probe PRODUCTS]
          INDEX JOIN  ONE-TO-MANY  C.CUSTOMERID = SO.CUSTOMERID [probe CUSTOMERS]
                      enum: JOIN_THRU_JOIN
            INDEX JOIN  ONE-TO-MANY  SO.ORDERID = OI.ORDERID    [probe SALESORDERS]
                        enum: JOIN_THRU_JOIN
              TABLE SCAN  ORDERITEMS   (7 rows)

    THE HEADLINE FINDING — HANA REORDERED THE JOIN
    ------------------------------------------------------------------------
        We wrote     :  SalesOrders -> Customers -> OrderItems -> Products
        HANA executed:  OrderItems  -> SalesOrders -> Customers -> Products

    The query begins at ORDERITEMS, which is the table we mentioned THIRD.
    SQL is declarative and this plan is the proof: the FROM clause expresses
    what to compute, not the sequence in which to compute it.

    WHY ORDERITEMS FIRST
    OrderItems is the lowest-granularity table (7 rows, one per order line) and
    it is the only table holding foreign keys to BOTH remaining branches. Every
    other table can be reached from it by a single primary-key probe. Driving
    from it means the row count never grows: 7 rows enter the bottom scan and
    7 rows leave the top join. Had HANA driven from Customers instead, the
    OrderItems join would have expanded 5 rows into 7 mid-plan.

    FURTHER OBSERVATIONS
    1. JOIN_THRU_JOIN on the two inner joins is the named rewrite that permitted
       this reassociation. It appears on operators 4 and 5 but NOT on the
       topmost join (operator 3), which is the join HANA kept in place.
    2. The join directions flip to suit the new order. Q3 recorded
       MANY-TO-ONE on SO.CUSTOMERID = C.CUSTOMERID; here the same logical join
       is recorded ONE-TO-MANY, because we now arrive from the customer side.
       Same predicate, opposite traversal.
    3. FOUR tables, but only ONE table scan. The other three are index probes.
       Three joins were resolved without building a single hash table.
    4. COST SCALING: Q3 (1 join) = 1.64e-6, Q4 (3 joins) = 3.56e-6. That is
       2.2x cost for 3x the joins — sublinear. Each additional PK probe is
       cheaper than the one before it because the driving row count is fixed. */


/* ############################################################################
   Q5 — AGGREGATION OVER A JOIN
   Business question: revenue and units per category?
   Plan: plans/Q5_agg_over_join.csv      Result: screenshots/Q5_agg_over_join.jpg
   ######################################################################### */

SELECT
    p.Category,
    COUNT(DISTINCT oi.OrderID) AS ItemsSold,      -- see naming caveat below
    SUM(oi.Quantity)           AS TotalUnits,
    SUM(oi.LineTotal)          AS TotalRevenue
FROM OrderItems oi
JOIN Products p ON oi.ProductID = p.ProductID
GROUP BY p.Category
ORDER BY TotalRevenue DESC;

/*  OBSERVED PLAN                                    engine: HEX   cost: 6.72e-6
    ------------------------------------------------------------------------
    PROJECT
      ORDER BY   SUM(OI.LINETOTAL) DESC
        AGGREGATION  GROUPING: P.CATEGORY
                     AGGS: COUNT(DISTINCT OI.ORDERID), SUM(QUANTITY), SUM(LINETOTAL)
                     props: VALUE_ID GROUPING          <-- note what is MISSING
          INDEX JOIN MANY-TO-ONE  OI.PRODUCTID = P.PRODUCTID   [probe PRODUCTS]
            TABLE SCAN ORDERITEMS  (7 rows)

    OBSERVATIONS
    1. PERFECT_HASH IS ABSENT HERE, and it was present in Q1. This is the most
       informative difference in the set. In Q1 the grouping key came straight
       off a base column, so HANA knew the exact dictionary cardinality up front
       and could size a collision-free table. Here the grouping key arrives
       through a join, so the distinct count is an ESTIMATE and HANA falls back
       to a general hash. Same GROUP BY on the same 3 categories, weaker
       guarantee, purely because a join sits underneath.
    2. AGGREGATION SITS ABOVE THE JOIN. HANA did NOT push the grouping below
       the join here. Contrast this directly with Q6, where the AGGR_THRU_JOIN
       rewrite does push aggregation under a join. Same optimizer, opposite
       decision, driven by whether the grouping key survives the pushdown.
    3. COUNT(DISTINCT) is the expensive aggregate in this list. It cannot be
       merged into the running sums; it needs its own distinct-value structure.
       Q5 costs 4.1x Q4 (6.72e-6 vs 1.64e-6 for Q3, 1.9x Q4) despite touching
       fewer tables than Q4 — the aggregation, not the join, dominates.
    4. NAMING CAVEAT (a real defect in the query, left visible on purpose):
       the alias ItemsSold is wrong. COUNT(DISTINCT oi.OrderID) counts ORDERS,
       not items. Electronics shows ItemsSold = 3, but Electronics appears on
       3 order LINES across 3 distinct orders; the two happen to coincide in
       this dataset and would diverge the moment one order contained two
       Electronics lines. The honest name is DistinctOrders. Flagged rather
       than silently fixed, because the plan in /plans corresponds to this
       exact text.

    MOST EXPENSIVE NON-PATHOLOGICAL QUERY IN THE SET. */


/* ############################################################################
   Q6 — REPEATED SCALAR SUBQUERY   *** THE CENTRAL EXPERIMENT ***
   Hypothesis under test: if the same correlated subquery is written twice,
   does HANA detect it and compute it once?
   Plan: plans/Q6_repeated_subquery.csv Result: screenshots/Q6_repeated_subquery.jpg
   ######################################################################### */

SELECT
    c.CustomerName,
    (SELECT SUM(oi.LineTotal)
       FROM OrderItems oi
       JOIN SalesOrders so ON oi.OrderID = so.OrderID
      WHERE so.CustomerID = c.CustomerID)                 AS TotalSpent,
    CASE WHEN (SELECT SUM(oi.LineTotal)
                 FROM OrderItems oi
                 JOIN SalesOrders so ON oi.OrderID = so.OrderID
                WHERE so.CustomerID = c.CustomerID) > 1000
         THEN 'High Value' ELSE 'Standard' END             AS CutomerTier
FROM Customers c;

/*  OBSERVED PLAN                                    engine: HEX   cost: 7.42e-6
    ------------------------------------------------------------------------
    PROJECT
      HASH JOIN (LEFT OUTER)   C.CUSTOMERID = SO.CUSTOMERID
                               HASH SIZE: 5, RIGHT SIDE HASH, PERFECT_HASH
                               enum: AGGR_THRU_JOIN
        |
        +-- [branch A]  INDEX JOIN (LEFT OUTER)  C.CUSTOMERID = SO.CUSTOMERID
        |                 AGGREGATION  GROUPING: SO.CUSTOMERID, SUM(OI.LINETOTAL)
        |                   INDEX JOIN  OI.ORDERID = SO.ORDERID
        |                     TABLE SCAN  ORDERITEMS      <-- scan #1
        |
        +-- [branch B]  AGGREGATION  GROUPING: SO.CUSTOMERID, SUM(OI.LINETOTAL)
                          INDEX JOIN  OI.ORDERID = SO.ORDERID
                            TABLE SCAN  ORDERITEMS        <-- scan #2

    VERDICT — TWO ANSWERS, AND THEY POINT OPPOSITE WAYS
    ------------------------------------------------------------------------
    (a) DECORRELATION: SUCCEEDED, and impressively so.
        We wrote a correlated scalar subquery, which reads as "for each of the
        5 customers, run this join and sum". That is NOT what executes. The
        AGGR_THRU_JOIN rewrite turned it into a single grouped aggregation
        (GROUP BY so.CustomerID) computed ONCE for all customers and then
        LEFT OUTER joined back to Customers. Per-row execution was eliminated.
        The LEFT OUTER is HANA preserving scalar-subquery semantics: a customer
        with no orders must yield NULL, not vanish.

    (b) COMMON SUBEXPRESSION ELIMINATION: DID NOT HAPPEN.
        Operators 4 and 7 are byte-identical AGGREGATION nodes. Each has its
        own INDEX JOIN and its own TABLE SCAN of ORDERITEMS beneath it. The
        two branches are then stitched together by the top HASH JOIN.
        ORDERITEMS IS SCANNED TWICE. The identical subquery was computed twice.

        This CONTRADICTS the common claim that "the optimizer will spot the
        repeated subquery for you". It did not. Both identical subtrees cost
        2.47e-6 each, and their sum is most of the query's 7.42e-6 total.

    WHY THE TOP JOIN IS A HASH JOIN AND NOT AN INDEX JOIN
    Branch B produces a computed aggregate, not a stored table, so there is no
    index to probe. HANA must build a hash table (HASH SIZE: 5, RIGHT SIDE
    HASH). This extra hash build exists ONLY because the subquery was duplicated
    — it is the structural cost of the missing deduplication.

    PRACTICAL CONSEQUENCE
    Rewriting with a CTE collapses branch B entirely:

        WITH spend AS (
            SELECT so.CustomerID, SUM(oi.LineTotal) AS TotalSpent
            FROM   OrderItems oi
            JOIN   SalesOrders so ON oi.OrderID = so.OrderID
            GROUP  BY so.CustomerID)
        SELECT c.CustomerName, s.TotalSpent,
               CASE WHEN s.TotalSpent > 1000 THEN 'High Value'
                    ELSE 'Standard' END AS CustomerTier
        FROM   Customers c
        LEFT   JOIN spend s ON s.CustomerID = c.CustomerID;

    NOT PROVEN: the CTE variant has not been EXPLAIN'd in this repo, so no
    measured speedup is claimed. What IS proven is that the current plan
    contains two identical subtrees where one would suffice.

    RESULT NOTE: TotalSpent recomputes from line items and so reports
    Nordic 2119.88 and Rhine 2021.90 — both higher than SUM(SalesOrders.
    TotalValue) would give. See the data-quality defect documented at the
    bottom of 01_schema_and_seed.sql. The query is right; the header column
    is stale.

    TYPO PRESERVED: the alias reads CutomerTier in the executed statement.
    Left as-is so the SQL matches the captured plan exactly. */


/* ############################################################################
   Q7 — EXISTS  (the semi-join experiment)
   Hypothesis under test: EXISTS reads as "run the subquery once per row".
   Does HANA actually execute it that way?
   Plan: plans/Q7_exists_semijoin.csv  Result: screenshots/Q7_exists_semijoin.jpg
   ######################################################################### */

SELECT c.CustomerName, c.Region
FROM Customers c
WHERE EXISTS (
    SELECT 1 FROM SalesOrders so WHERE so.CustomerID = c.CustomerID
);

/*  OBSERVED PLAN                                    engine: HEX   cost: 6.54e-7
    ------------------------------------------------------------------------
    PROJECT
      INDEX JOIN (SEMI)  ONE-TO-MANY  C.CUSTOMERID = SO.CUSTOMERID
                         LEFT SIDE INDEX
                         (est. output 4.5 rows)
        TABLE SCAN  SALESORDERS  (6 rows)

    VERDICT — HYPOTHESIS CONFIRMED. The rewrite happened.
    ------------------------------------------------------------------------
    1. The operator is literally named INDEX JOIN (SEMI). There is no loop, no
       subplan, no per-row re-execution. The correlated EXISTS became a single
       set operation.
    2. SEMI is the semantic guarantee that makes it correct: a semi-join emits
       each left row AT MOST ONCE and stops probing on the first match. That is
       exactly EXISTS semantics. A plain join would have returned Nordic Retail
       twice (it has 2 orders); the result set correctly shows it once.
    3. SELECT 1 is never evaluated. The projected column list is
       (CUSTOMERNAME, REGION) only. HANA understood that the subquery's SELECT
       list is irrelevant to EXISTS and discarded it — writing SELECT * instead
       of SELECT 1 would produce the same plan.
    4. ESTIMATED vs ACTUAL: OUTPUT_SIZE is 4.5 — a fractional row count, which
       can only be an estimate. The actual result is 5 rows. HANA under-
       estimated by 10% because its selectivity model assumes independence and
       cannot know that all 5 customers happen to have orders. Worth recording:
       the numbers in these plans are the optimizer's beliefs, not measurements.
    5. COST: 6.54e-7 — the cheapest query that touches two tables, 2.5x cheaper
       than the equivalent-looking Q3 join. Semi-join early-exit is why.

    DIRECT COMPARISON WITH Q6
    Q6 and Q7 both contain a correlated subquery over the same customer key.
    Q7 costs 6.54e-7; Q6 costs 7.42e-6 — 11x more. The gap is not "EXISTS is
    faster than SUM". It is that Q7's single subquery was rewritten into one
    set operation, while Q6's DUPLICATED subquery was rewritten into two.
    ------------------------------------------------------------------------ */


/* ============================================================================
   COST SUMMARY  (SUBTREE_COST at root, unitless optimizer estimate)

     Q2  filter pushdown ......  0.089e-6   1.0x   baseline
     Q7  EXISTS semi-join .....  0.654e-6   7.3x
     Q1  single-table agg .....  1.347e-6  15.1x
     Q3  two-table join .......  1.637e-6  18.3x
     Q4  four-table join ......  3.564e-6  39.9x
     Q5  agg over join ........  6.720e-6  75.2x
     Q6  repeated subquery ....  7.418e-6  83.1x   <- duplicated work

   Read with care: on 23 rows these are estimates, and the ordering matters
   far more than the magnitudes.
   ========================================================================= */
