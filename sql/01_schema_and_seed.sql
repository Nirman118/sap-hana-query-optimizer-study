/* ============================================================================
   01_SCHEMA_AND_SEED.SQL
   SAP HANA Cloud — Order-to-Cash sample schema
   ----------------------------------------------------------------------------
   Target   : SAP HANA Cloud (HSF_DB), schema NSHARMA
   Client   : SAP HANA Database Explorer
   Purpose  : Minimal but relationally complete dataset used to study the
              HANA HEX optimizer. Deliberately tiny (23 rows total) so that
              every EXPLAIN PLAN fits on one screen and every operator can
              be reasoned about by hand.

   Storage note: all four tables are COLUMN tables. This is the HANA default
   for analytics and it is what makes the plans in /plans interesting —
   the column store gives the optimizer dictionary-encoded value IDs, which
   is why aggregations show up as VALUE_ID GROUPING / PERFECT_HASH.
   ========================================================================= */


/* ---------------------------------------------------------------------------
   1. DIMENSION — CUSTOMERS (the buyer)
   ------------------------------------------------------------------------ */
CREATE COLUMN TABLE Customers (
    CustomerID   INTEGER       PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    Region       NVARCHAR(50),
    CreditLimit  DECIMAL(15,2),
    CreatedAt    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

/* ---------------------------------------------------------------------------
   2. DIMENSION — PRODUCTS (what is sold)
   ------------------------------------------------------------------------ */
CREATE COLUMN TABLE Products (
    ProductID   INTEGER       PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category    NVARCHAR(50),
    UnitPrice   DECIMAL(10,2) NOT NULL,
    StockQty    INTEGER       DEFAULT 0
);

/* ---------------------------------------------------------------------------
   3. FACT HEADER — SALESORDERS (one row per order)
   ------------------------------------------------------------------------ */
CREATE COLUMN TABLE SalesOrders (
    OrderID    INTEGER      PRIMARY KEY,
    CustomerID INTEGER      NOT NULL,
    OrderDate  DATE         NOT NULL,
    Status     NVARCHAR(20) DEFAULT 'OPEN',
    TotalValue DECIMAL(15,2),
    CONSTRAINT fk_order_customer FOREIGN KEY (CustomerID)
        REFERENCES Customers(CustomerID)
);

/* ---------------------------------------------------------------------------
   4. FACT LINE — ORDERITEMS (many rows per order)
   ------------------------------------------------------------------------
   The declared foreign keys matter for this study: HANA uses referential
   constraints to prove join cardinality. Every "MANY-TO-ONE INDEX JOIN"
   in /plans is a direct consequence of these two constraints.
   ------------------------------------------------------------------------ */
CREATE COLUMN TABLE OrderItems (
    OrderItems INTEGER       PRIMARY KEY,   -- surrogate line key
    OrderID    INTEGER       NOT NULL,
    ProductID  INTEGER       NOT NULL,
    Quantity   INTEGER       NOT NULL,
    LineTotal  DECIMAL(15,2),
    CONSTRAINT fk_item_order   FOREIGN KEY (OrderID)   REFERENCES SalesOrders(OrderID),
    CONSTRAINT fk_item_product FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);


/* ---------------------------------------------------------------------------
   VERIFY — all four objects created as COLUMN tables
   ------------------------------------------------------------------------ */
SELECT TABLE_NAME, TABLE_TYPE
FROM   SYS.TABLES
WHERE  SCHEMA_NAME = CURRENT_SCHEMA
  AND  TABLE_NAME IN ('CUSTOMERS','PRODUCTS','SALESORDERS','ORDERITEMS');


/* ===========================================================================
   SEED DATA
   ======================================================================== */

-- Customers (5)
INSERT INTO Customers VALUES (1, 'Nordic Retail GmbH',   'Europe',        50000.00, CURRENT_TIMESTAMP);
INSERT INTO Customers VALUES (2, 'Alpine Trading Co',    'Europe',        30000.00, CURRENT_TIMESTAMP);
INSERT INTO Customers VALUES (3, 'Pacific Distributors', 'APAC',          75000.00, CURRENT_TIMESTAMP);
INSERT INTO Customers VALUES (4, 'Rhine Logistics AG',   'Europe',        45000.00, CURRENT_TIMESTAMP);
INSERT INTO Customers VALUES (5, 'Atlas Wholesale Inc',  'North America', 60000.00, CURRENT_TIMESTAMP);

-- Products (5) — three categories, deliberately unbalanced
INSERT INTO Products VALUES (101, 'Industrial Sensor A1', 'Electronics', 149.99,  500);
INSERT INTO Products VALUES (102, 'Hydraulic Pump B2',    'Machinery',   899.50,  120);
INSERT INTO Products VALUES (103, 'Steel Bracket C3',     'Hardware',     12.75, 5000);
INSERT INTO Products VALUES (104, 'Control Valve D4',     'Machinery',   320.00,  300);
INSERT INTO Products VALUES (105, 'Safety Relay E5',      'Electronics',  65.25,  800);

-- SalesOrders (6) — customer 1 has two orders, customers 2..5 have one each
INSERT INTO SalesOrders VALUES (1001, 1, '2026-06-01', 'CLOSED', 1799.48);
INSERT INTO SalesOrders VALUES (1002, 2, '2026-06-03', 'CLOSED',  899.50);
INSERT INTO SalesOrders VALUES (1003, 3, '2026-06-05', 'OPEN',     63.75);
INSERT INTO SalesOrders VALUES (1004, 1, '2026-06-10', 'OPEN',    320.00);
INSERT INTO SalesOrders VALUES (1005, 4, '2026-06-12', 'CLOSED', 2015.75);
INSERT INTO SalesOrders VALUES (1006, 5, '2026-06-15', 'OPEN',    130.50);

-- OrderItems (7) — order 1005 is the only multi-line order
INSERT INTO OrderItems VALUES (1, 1001, 101, 12, 1799.88);
INSERT INTO OrderItems VALUES (2, 1002, 102,  1,  899.50);
INSERT INTO OrderItems VALUES (3, 1003, 103,  5,   63.75);
INSERT INTO OrderItems VALUES (4, 1004, 104,  1,  320.00);
INSERT INTO OrderItems VALUES (5, 1005, 101, 10, 1499.90);
INSERT INTO OrderItems VALUES (6, 1005, 105,  8,  522.00);
INSERT INTO OrderItems VALUES (7, 1006, 105,  2,  130.50);


/* ---------------------------------------------------------------------------
   VERIFY — expected 5 / 5 / 6 / 7
   ------------------------------------------------------------------------ */
SELECT 'Customers' AS TableName, COUNT(*) AS RowCnt FROM Customers
UNION ALL SELECT 'Products',    COUNT(*) FROM Products
UNION ALL SELECT 'SalesOrders', COUNT(*) FROM SalesOrders
UNION ALL SELECT 'OrderItems',  COUNT(*) FROM OrderItems;


/* ---------------------------------------------------------------------------
   SMOKE TEST — the full 4-table join must return exactly 7 rows
   (one per order line). If it returns fewer, a foreign key is orphaned.
   ------------------------------------------------------------------------ */
SELECT c.CustomerName, so.OrderID, p.ProductName, oi.Quantity, oi.LineTotal
FROM   SalesOrders so
JOIN   Customers  c  ON so.CustomerID = c.CustomerID
JOIN   OrderItems oi ON so.OrderID    = oi.OrderID
JOIN   Products   p  ON oi.ProductID  = p.ProductID
ORDER  BY so.OrderID;


/* ---------------------------------------------------------------------------
   KNOWN DATA-QUALITY DEFECT (intentionally left in place)
   ------------------------------------------------------------------------
   SalesOrders.TotalValue is a denormalised copy of SUM(OrderItems.LineTotal)
   and it does NOT reconcile for two orders:

       OrderID 1001 : header 1799.48   lines 1799.88   delta -0.40
       OrderID 1005 : header 2015.75   lines 2021.90   delta -6.15

   The line values are the correct ones (12 x 149.99 = 1799.88;
   10 x 149.99 + 8 x 65.25 = 1499.90 + 522.00 = 2021.90).

   This is preserved on purpose. It is what makes Q6 in
   02_queries_annotated.sql meaningful: that query recomputes the total from
   the line items instead of trusting the header, and therefore returns
   different numbers than a naive SUM(TotalValue) would. Reconciliation
   query to reproduce the defect:

       SELECT so.OrderID, so.TotalValue,
              SUM(oi.LineTotal) AS LineSum,
              so.TotalValue - SUM(oi.LineTotal) AS Delta
       FROM   SalesOrders so
       JOIN   OrderItems  oi ON oi.OrderID = so.OrderID
       GROUP  BY so.OrderID, so.TotalValue
       HAVING so.TotalValue <> SUM(oi.LineTotal);
   ------------------------------------------------------------------------ */
