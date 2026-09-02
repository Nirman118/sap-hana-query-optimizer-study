/* ============================================================================
   03_SCALING_10K_100K_1M.SQL
   Generation scripts for the three scaled tiers used throughout the report.
   Tables are scaled proportionally, not equally — see report Section 4.3
   for the reasoning. Each tier clears the previous one's data before
   generating (children deleted before parents, since foreign keys forbid
   TRUNCATE on a referenced table).
   ========================================================================= */


/* ============================================================================
   TIER 1 — 10,000 rows in OrderItems
   Customers 1,000 | Products 200 | SalesOrders 4,000 | OrderItems 10,000
   ========================================================================= */

-- Step 1: clear the baseline data (children before parents)
TRUNCATE TABLE OrderItems;
TRUNCATE TABLE SalesOrders;
TRUNCATE TABLE NSHARMA.PRODUCTS;
TRUNCATE TABLE NSHARMA.CUSTOMERS;
-- Note: a table referenced by a foreign key anywhere cannot be TRUNCATEd,
-- even if the referencing table is itself empty — DELETE is the fallback.
DELETE FROM OrderItems;
DELETE FROM SalesOrders;
DELETE FROM NSHARMA.PRODUCTS;
DELETE FROM NSHARMA.CUSTOMERS;

-- Step 2: Products (200)
INSERT INTO NSHARMA.PRODUCTS (ProductID, ProductName, Category, UnitPrice, StockQty)
SELECT
	GENERATED_PERIOD_START + 1 AS ProductID,
	'Product_' || (GENERATED_PERIOD_START + 1) AS ProductName,
	CASE MOD(GENERATED_PERIOD_START, 4)
		WHEN 0 THEN 'Electronics'
		WHEN 1 THEN 'Machinery'
		WHEN 2 THEN 'Hardware'
		ELSE 'Consumables'
	END AS Category,
	ROUND(RAND() * 890 + 10, 2) AS UnitPrice,
	CAST(RAND() * 1000 AS INTEGER) AS StockQty
FROM SERIES_GENERATE_INTEGER(1, 0, 200);

-- Step 3: Customers (1,000)
INSERT INTO Customers (CustomerID, CustomerName, Region, CreditLimit, CreatedAt)
SELECT
	GENERATED_PERIOD_START + 1 AS CustomerID,
	'Customer_' || (GENERATED_PERIOD_START + 1) AS CustomerName,
	CASE MOD(GENERATED_PERIOD_START, 4)
		WHEN 0 THEN 'Europe'
		WHEN 1 THEN 'North America'
		WHEN 2 THEN 'APAC'
		ELSE 'South America'
	END AS Region,
	ROUND(RAND() * 90000 + 10000, 2) AS CreditLimit,
	CURRENT_TIMESTAMP
FROM SERIES_GENERATE_INTEGER(1, 0, 1000);

-- Step 4: SalesOrders (4,000), referencing the 1,000 real customers
INSERT INTO SalesOrders (OrderID, CustomerID, OrderDate, Status, TotalValue)
SELECT
	GENERATED_PERIOD_START + 1 AS OrderID,
	MOD(GENERATED_PERIOD_START, 1000) + 1 AS CustomerID,
	ADD_DAYS('2026-01-01', MOD(GENERATED_PERIOD_START, 180)) AS OrderDate,
	CASE MOD(GENERATED_PERIOD_START, 3)
		WHEN 0 THEN 'OPEN'
		WHEN 1 THEN 'CLOSED'
		ELSE 'SHIPPED'
	END AS Status,
	0 AS TotalValue
FROM SERIES_GENERATE_INTEGER(1, 0, 4000);

-- Step 5: OrderItems (10,000 — the target figure for this tier)
INSERT INTO OrderItems (OrderItemID, OrderID, ProductID, Quantity, LineTotal)
SELECT
	GENERATED_PERIOD_START + 1 AS OrderItemID,
	MOD(GENERATED_PERIOD_START, 4000) + 1 AS OrderID,
	MOD(GENERATED_PERIOD_START, 200) + 1 AS ProductID,
	CAST(RAND() * 20 + 1 AS INTEGER) AS Quantity,
	0 AS LineTotal
FROM SERIES_GENERATE_INTEGER(1, 0, 10000);

/* ----------------------------------------------------------------------------
   DOCUMENTED MISTAKE (report Section 9.2)
   The INSERT above failed the first time with "invalid column name
   ORDERITEMID" on a table where that column plainly existed. It did not:
   a typo in the original CREATE TABLE had named the primary key column
   ORDERITEMS, matching the table name. SYS.TABLE_COLUMNS confirmed this in
   seconds; RENAME COLUMN fixed it, and the Step 5 insert above was re-run.
   --------------------------------------------------------------------------- */
SELECT COLUMN_NAME, POSITION, DATA_TYPE_NAME
FROM SYS.TABLE_COLUMNS
WHERE TABLE_NAME = 'ORDERITEMS' AND SCHEMA_NAME = CURRENT_SCHEMA
ORDER BY POSITION;

RENAME COLUMN OrderItems.ORDERITEMS TO OrderItemID;

-- Step 6: back-fill computed values so LineTotal and TotalValue are internally
-- consistent (Quantity * UnitPrice, and the sum of an order's lines)
UPDATE OrderItems oi
SET LineTotal = (SELECT oi.Quantity * p.UnitPrice FROM Products p WHERE p.ProductID = oi.ProductID)
WHERE EXISTS (SELECT 1 FROM Products p WHERE p.ProductID = oi.ProductID);

UPDATE SalesOrders so
SET TotalValue = (SELECT SUM(oi.LineTotal) FROM OrderItems oi WHERE oi.OrderID = so.OrderID)
WHERE EXISTS (SELECT 1 FROM OrderItems oi WHERE oi.OrderID = so.OrderID);

-- Step 7: verify — expect 1,000 / 200 / 4,000 / 10,000
SELECT 'Customers' AS TableName, COUNT(*) AS RowCount FROM Customers
UNION ALL SELECT 'Products', COUNT(*) FROM Products
UNION ALL SELECT 'SalesOrders', COUNT(*) FROM SalesOrders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM OrderItems;


/* ============================================================================
   TIER 2 — 100,000 rows in OrderItems
   Customers 10,000 | Products 2,000 | SalesOrders 40,000 | OrderItems 100,000
   ========================================================================= */

-- Step 1: clear the 10K data
DELETE FROM OrderItems;
DELETE FROM SalesOrders;
DELETE FROM Products;
DELETE FROM Customers;

-- Step 2: Products (2,000)
INSERT INTO Products (ProductID, ProductName, Category, UnitPrice, StockQty)
SELECT
    GENERATED_PERIOD_START + 1,
    'Product_' || (GENERATED_PERIOD_START + 1),
    CASE MOD(GENERATED_PERIOD_START, 4)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Machinery'
        WHEN 2 THEN 'Hardware'
        ELSE 'Consumables'
    END,
    ROUND(RAND() * 890 + 10, 2),
    CAST(RAND() * 1000 AS INTEGER)
FROM SERIES_GENERATE_INTEGER(1, 0, 2000);

-- Step 3: Customers (10,000)
INSERT INTO Customers (CustomerID, CustomerName, Region, CreditLimit, CreatedAt)
SELECT
    GENERATED_PERIOD_START + 1,
    'Customer_' || (GENERATED_PERIOD_START + 1),
    CASE MOD(GENERATED_PERIOD_START, 4)
        WHEN 0 THEN 'Europe'
        WHEN 1 THEN 'North America'
        WHEN 2 THEN 'APAC'
        ELSE 'South America'
    END,
    ROUND(RAND() * 90000 + 10000, 2),
    CURRENT_TIMESTAMP
FROM SERIES_GENERATE_INTEGER(1, 0, 10000);

-- Step 4: SalesOrders (40,000)
INSERT INTO SalesOrders (OrderID, CustomerID, OrderDate, Status, TotalValue)
SELECT
    GENERATED_PERIOD_START + 1,
    MOD(GENERATED_PERIOD_START, 10000) + 1,
    ADD_DAYS('2026-01-01', MOD(GENERATED_PERIOD_START, 180)),
    CASE MOD(GENERATED_PERIOD_START, 3)
        WHEN 0 THEN 'OPEN' WHEN 1 THEN 'CLOSED' ELSE 'SHIPPED'
    END,
    0
FROM SERIES_GENERATE_INTEGER(1, 0, 40000);

-- Step 5: OrderItems (100,000 — the target figure for this tier)
INSERT INTO OrderItems (OrderItemID, OrderID, ProductID, Quantity, LineTotal)
SELECT
	GENERATED_PERIOD_START + 1,
	MOD(GENERATED_PERIOD_START, 40000) + 1,
	MOD(GENERATED_PERIOD_START, 2000) + 1,
	CAST(RAND() * 20 + 1 AS INTEGER),
	0
FROM SERIES_GENERATE_INTEGER(1, 0, 100000);

-- Step 6: back-fill (same logic as the 10K tier)
UPDATE OrderItems oi
SET LineTotal = (SELECT oi.Quantity * p.UnitPrice FROM Products p WHERE p.ProductID = oi.ProductID)
WHERE EXISTS (SELECT 1 FROM Products p WHERE p.ProductID = oi.ProductID);

UPDATE SalesOrders so
SET TotalValue = (SELECT SUM(oi.LineTotal) FROM OrderItems oi WHERE oi.OrderID = so.OrderID)
WHERE EXISTS (SELECT 1 FROM OrderItems oi WHERE oi.OrderID = so.OrderID);

-- Step 7: verify — expect 10,000 / 2,000 / 40,000 / 100,000
SELECT 'Customers' AS TableName, COUNT(*) AS RowCount FROM Customers
UNION ALL SELECT 'Products', COUNT(*) FROM Products
UNION ALL SELECT 'SalesOrders', COUNT(*) FROM SalesOrders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM OrderItems;


/* ============================================================================
   TIER 3 — 1,000,000 rows in OrderItems
   Customers 100,000 | Products 20,000 | SalesOrders 400,000 | OrderItems 1,000,000
   ========================================================================= */

-- Step 1: clear the 100K data
DELETE FROM OrderItems;
DELETE FROM SalesOrders;
DELETE FROM Products;
DELETE FROM Customers;

-- Step 2: Products (20,000)
INSERT INTO Products (ProductID, ProductName, Category, UnitPrice, StockQty)
SELECT
    GENERATED_PERIOD_START + 1,
    'Product_' || (GENERATED_PERIOD_START + 1),
    CASE MOD(GENERATED_PERIOD_START, 4)
        WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Machinery'
        WHEN 2 THEN 'Hardware' ELSE 'Consumables'
    END,
    ROUND(RAND() * 890 + 10, 2),
    CAST(RAND() * 1000 AS INTEGER)
FROM SERIES_GENERATE_INTEGER(1, 0, 20000);

-- Step 3: Customers (100,000)
INSERT INTO Customers (CustomerID, CustomerName, Region, CreditLimit, CreatedAt)
SELECT
    GENERATED_PERIOD_START + 1,
    'Customer_' || (GENERATED_PERIOD_START + 1),
    CASE MOD(GENERATED_PERIOD_START, 4)
        WHEN 0 THEN 'Europe' WHEN 1 THEN 'North America'
        WHEN 2 THEN 'APAC' ELSE 'South America'
    END,
    ROUND(RAND() * 90000 + 10000, 2),
    CURRENT_TIMESTAMP
FROM SERIES_GENERATE_INTEGER(1, 0, 100000);

-- Step 4: SalesOrders (400,000)
INSERT INTO SalesOrders (OrderID, CustomerID, OrderDate, Status, TotalValue)
SELECT
    GENERATED_PERIOD_START + 1,
    MOD(GENERATED_PERIOD_START, 100000) + 1,
    ADD_DAYS('2026-01-01', MOD(GENERATED_PERIOD_START, 180)),
    CASE MOD(GENERATED_PERIOD_START, 3) WHEN 0 THEN 'OPEN' WHEN 1 THEN 'CLOSED' ELSE 'SHIPPED' END,
    0
FROM SERIES_GENERATE_INTEGER(1, 0, 400000);

-- Step 5: OrderItems (1,000,000 — the target figure for this tier)
INSERT INTO OrderItems (OrderItemID, OrderID, ProductID, Quantity, LineTotal)
SELECT
    GENERATED_PERIOD_START + 1,
    MOD(GENERATED_PERIOD_START, 400000) + 1,
    MOD(GENERATED_PERIOD_START, 20000) + 1,
    CAST(RAND() * 20 + 1 AS INTEGER),
    0
FROM SERIES_GENERATE_INTEGER(1, 0, 1000000);

-- Step 6: back-fill
UPDATE OrderItems oi
SET LineTotal = (SELECT oi.Quantity * p.UnitPrice FROM Products p WHERE p.ProductID = oi.ProductID)
WHERE EXISTS (SELECT 1 FROM Products p WHERE p.ProductID = oi.ProductID);

UPDATE SalesOrders so
SET TotalValue = (SELECT SUM(oi.LineTotal) FROM OrderItems oi WHERE oi.OrderID = so.OrderID)
WHERE EXISTS (SELECT 1 FROM OrderItems oi WHERE oi.OrderID = so.OrderID);

-- Step 7: verify — expect 100,000 / 20,000 / 400,000 / 1,000,000
SELECT 'Customers' AS TableName, COUNT(*) AS RowCount FROM Customers
UNION ALL SELECT 'Products', COUNT(*) FROM Products
UNION ALL SELECT 'SalesOrders', COUNT(*) FROM SalesOrders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM OrderItems;
