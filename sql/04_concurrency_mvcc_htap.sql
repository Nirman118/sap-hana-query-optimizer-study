/* ============================================================================
   04_CONCURRENCY_MVCC_HTAP.SQL
   Two tests, both run at the 1M tier, both requiring two separate console
   connections open at the same time. See report Section 7.
   ========================================================================= */


/* ----------------------------------------------------------------------------
   TEST 1 — MVCC: does a writer block a reader? (report Section 7.1)
   Run with autocommit OFF on Console A (set in the console's connection
   settings, not in SQL — HANA has no START TRANSACTION statement, and with
   autocommit on every statement commits immediately, leaving nothing open
   to observe).
   --------------------------------------------------------------------------- */

-- Console A: update a row and leave it uncommitted
UPDATE OrderItems SET Quantity = 77777 WHERE OrderItemID = 1;
-- (do not run COMMIT yet)

-- Console B, on a separate connection, immediately after:
SELECT OrderItemID, Quantity FROM OrderItems WHERE OrderItemID = 1;
-- Expected while A is uncommitted: returns the PREVIOUS value, no wait.

-- Console A, once B's read above has been observed:
COMMIT;

-- Console B, re-run the same SELECT:
SELECT OrderItemID, Quantity FROM OrderItems WHERE OrderItemID = 1;
-- Expected after commit: returns 77777.


/* ----------------------------------------------------------------------------
   TEST 2 — HTAP mixed load: does a large concurrent write slow down an
   analytical read? (report Section 7.2)

   Run Console A's insert and Console B's aggregation in separate browser
   windows so the aggregation can be started while the insert is genuinely
   still running. Smaller inserts finish in tens of milliseconds — too fast
   to overlap — which is why the final version below uses 2,000,000 rows.
   --------------------------------------------------------------------------- */

-- Console A: rapid transactional writes (early, smaller attempt — 10,000 rows)
INSERT INTO OrderItems (OrderItemID, OrderID, ProductID, Quantity, LineTotal)
SELECT (SELECT MAX(OrderItemID) FROM OrderItems) + GENERATED_PERIOD_START + 1,
       MOD(GENERATED_PERIOD_START, 400000) + 1,
       MOD(GENERATED_PERIOD_START, 20000) + 1,
       5, 100
FROM SERIES_GENERATE_INTEGER(1, 0, 10000);

-- Second attempt, 10,000 rows, run once a workload class was in place
-- (see 05_workload_governance.sql) to test the governed case
INSERT INTO OrderItems (OrderItemID, OrderID, ProductID, Quantity, LineTotal)
SELECT 3000000 + GENERATED_PERIOD_START, MOD(GENERATED_PERIOD_START, 400000) + 1,
       MOD(GENERATED_PERIOD_START, 20000) + 1, 5, 100
FROM SERIES_GENERATE_INTEGER(1, 0, 10000);

-- Final version — 2,000,000 rows, large enough that Console B's aggregation
-- can be launched while this is still executing. This is the run reported
-- in Table 8/9 of the report.
INSERT INTO OrderItems (OrderItemID, OrderID, ProductID, Quantity, LineTotal)
SELECT (SELECT MAX(OrderItemID) FROM OrderItems) + GENERATED_PERIOD_START + 1,
       MOD(GENERATED_PERIOD_START, 400000) + 1, MOD(GENERATED_PERIOD_START, 20000) + 1, 5, 100
FROM SERIES_GENERATE_INTEGER(1, 0, 2000000);

-- Console B, launched while Console A's 2,000,000-row insert is running:
SELECT p.Category, SUM(oi.LineTotal) AS Revenue, COUNT(*) AS Items
FROM OrderItems oi JOIN Products p ON oi.ProductID = p.ProductID
GROUP BY p.Category
ORDER BY Revenue DESC;
-- This is the aggregation timed in Table 8 (ungoverned) and re-run again in
-- Table 9 with the workload class active (see 05_workload_governance.sql).
