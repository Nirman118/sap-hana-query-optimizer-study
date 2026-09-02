/* ============================================================================
   02_QUERIES_BASELINE.SQL
   The eight queries, run against the 7-row baseline schema (see
   01_schema_and_seed.sql). Each is captured with EXPLAIN PLAN at every
   scale tier; the baseline plans are the smallest and easiest to read by
   hand, which is why the baseline text is reproduced here in full.
   ========================================================================= */


-- Q1: What is our total inventory value across all products?
SELECT
	Category,
	COUNT(*) as ProductCount,
	SUM(UnitPrice*StockQty) as TotalInventoryValue
FROM Products
GROUP BY Category
ORDER BY TotalInventoryValue DESC;


-- Q2: Which products are running low on stock and need reordering?
SELECT
	ProductID,
	ProductName,
	Category,
	StockQty,
	UnitPrice
FROM Products
WHERE StockQty < 300
ORDER BY StockQty ASC;


-- Q3: Which customers have placed orders, and what is each order's date and status?
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


-- Q4: For each order, what products were purchased, and what is the total quantity?
-- This is the four-table join chain referenced throughout Section 5 of the report.
SELECT
	so.OrderID,
	c.CustomerName,
	p.ProductName,
	oi.Quantity,
	oi.LineTotal
FROM SalesOrders so
JOIN Customers c ON so.CustomerID = c.CustomerID
JOIN OrderItems oi ON so.OrderID = oi.OrderID
JOIN Products p ON oi.ProductID = p.ProductID
ORDER BY so.OrderID;


/* ----------------------------------------------------------------------------
   HINT DISCOVERY (report Section 6.1)
   The original plan assumed Oracle-style hint names (USE_HASH_JOIN,
   USE_NESTED_LOOP_JOIN); both are invalid in HANA and return error 468.
   The two queries below are how the correct name was found: querying the
   system catalogue directly rather than guessing a second time.
   --------------------------------------------------------------------------- */
SELECT SCHEMA_NAME, VIEW_NAME
FROM SYS.VIEWS
WHERE VIEW_NAME LIKE '%HINT%';

SELECT * FROM SYS.HINTS
WHERE HINT_NAME LIKE '%JOIN%' OR HINT_NAME LIKE '%HASH%' OR HINT_NAME LIKE '%LOOP%'
ORDER BY HINT_NAME;


-- Q4, forced into a nested loop join using the correct HANA hint name.
-- Compared against the optimizer's own Q4 plan above — this comparison is
-- the basis for the 46x / 386x / 3,352x penalty figures in report Section 6.2.
SELECT so.OrderID, c.CustomerName, p.ProductName, oi.Quantity, oi.LineTotal
FROM SalesOrders so
JOIN Customers c ON so.CustomerID = c.CustomerID
JOIN OrderItems oi ON so.OrderID = oi.OrderID
JOIN Products p ON oi.ProductID = p.ProductID
ORDER BY so.OrderID
WITH HINT(HEX_NESTED_LOOP_JOIN);


-- Q5: What is the total revenue per product category, and how many units of
-- each were sold?
SELECT
	p.Category,
	COUNT(DISTINCT oi.OrderID) as ItemsSold,
	SUM(oi.Quantity) as TotalUnits,
	SUM(oi.LineTotal) as TotalRevenue
FROM OrderItems oi
JOIN Products p ON oi.ProductID = p.ProductID
GROUP BY p.Category
ORDER BY TotalRevenue DESC;


-- Q6: the same correlated subquery written twice — once as a value, once
-- inside a CASE expression. The question under test: does HANA's optimizer
-- detect the repetition and compute it once? The plan shows it does not —
-- see report Section 5.6. ("CutomerTier" alias spelling is preserved exactly
-- as executed, since the plan and the report both reference it as written.)
SELECT
	c.CustomerName,
	(SELECT SUM(oi.LineTotal) FROM OrderItems oi JOIN SalesOrders so ON oi.OrderID=so.OrderID WHERE so.CustomerID=c.CustomerID) as TotalSpent,
	CASE WHEN (SELECT SUM(oi.LineTotal) FROM OrderItems oi JOIN SalesOrders so ON oi.OrderID=so.OrderID WHERE so.CustomerID=c.CustomerID)>1000
		 THEN 'High Value' ELSE 'Standard' END as CutomerTier
FROM Customers c;


-- Q7: EXISTS reads as though it should run once per outer row. HANA
-- rewrites it into a single semi-join instead — see report Section 5.3.
SELECT c.CustomerName, c.Region
FROM Customers c
WHERE EXISTS (
	SELECT 1 FROM SalesOrders so WHERE so.CustomerID = c.CustomerID
);


-- Q8: self-join with one equality condition and two inequality conditions,
-- written specifically to try to force a nested loop join naturally. The
-- optimizer splits the compound condition instead — see report Section 5.5.
SELECT so1.CustomerID, so1.OrderID AS LaterOrder, so2.OrderID AS EarlierOrder,
       so1.TotalValue, so2.TotalValue
FROM SalesOrders so1
JOIN SalesOrders so2
    ON so1.CustomerID = so2.CustomerID
    AND so1.OrderDate > so2.OrderDate
    AND so1.TotalValue > so2.TotalValue;
