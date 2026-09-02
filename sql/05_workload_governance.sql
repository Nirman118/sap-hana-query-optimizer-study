/* ============================================================================
   05_WORKLOAD_GOVERNANCE.SQL
   Creating a workload class, mapping it to a session, and verifying it is
   genuinely governing statements rather than just existing. See report
   Section 8. This file includes the failed first mapping attempt and the
   fix, in the order they actually happened, per report Section 8.2.
   ========================================================================= */


-- Drop any leftover objects from earlier troubleshooting before starting clean
DROP WORKLOAD MAPPING "ANALYTICS_MAPPING";
DROP WORKLOAD CLASS "ANALYTICS_LOW_PRIO";

-- There is no WORKLOAD_CLASS_PROPERTIES view in HANA — checked and ruled out
-- before finding the correct catalog views below.
SELECT SCHEMA_NAME, VIEW_NAME
FROM SYS.VIEWS
WHERE VIEW_NAME LIKE '%WORKLOAD%';

-- Create the class. STATEMENT MEMORY LIMIT and STATEMENT THREAD LIMIT are the
-- correct property names — CPU DEGREE OF PARALLELISM (the originally planned
-- property) does not exist in HANA.
CREATE WORKLOAD CLASS "ANALYTICS_LOW_PRIO"
SET 'STATEMENT MEMORY LIMIT' = '2',
    'STATEMENT THREAD LIMIT' = '2'
ENABLE;

-- Verify the class exists
SELECT * FROM WORKLOAD_CLASSES WHERE WORKLOAD_CLASS_NAME = 'ANALYTICS_LOW_PRIO';

/* ----------------------------------------------------------------------------
   FIRST MAPPING ATTEMPT — this is the one that looked correct and was not
   (report Section 8.2). Mapped on APPLICATION USER NAME, which a direct SQL
   console connection never sets, so the mapping matched no session at all.
   The first governed test showed a real slowdown, but it came from the
   concurrent write load, not from governance — confirmed by checking
   M_WORKLOAD_CLASS_STATISTICS and finding zero admitted statements.
   --------------------------------------------------------------------------- */
CREATE WORKLOAD MAPPING "ANALYTICS_MAPPING"
WORKLOAD CLASS "ANALYTICS_LOW_PRIO"
SET 'APPLICATION USER NAME' = 'NSHARMA';

-- Verify the mapping exists (it does — but existing is not the same as governing)
SELECT * FROM WORKLOAD_MAPPINGS WHERE WORKLOAD_CLASS_NAME = 'ANALYTICS_LOW_PRIO';

-- What actually diagnosed the problem: checking which session attribute the
-- connection really presents. This showed USER_NAME = NSHARMA and a
-- CLIENT_APPLICATION that is a fixed tool identifier — not APPLICATION USER
-- NAME, which is populated by application frameworks, not a direct console.
SELECT STATEMENT_STRING, WORKLOAD_CLASS_NAME, TOTAL_EXECUTION_TIME
FROM M_ACTIVE_STATEMENTS;

/* ----------------------------------------------------------------------------
   FIX — remap on USER NAME instead of APPLICATION USER NAME, then open a
   fresh session before retesting, since mappings are evaluated at connection
   time and are not applied retroactively to an already-open session.
   --------------------------------------------------------------------------- */
DROP WORKLOAD MAPPING "ANALYTICS_MAPPING";

CREATE WORKLOAD MAPPING "ANALYTICS_MAPPING"
WORKLOAD CLASS "ANALYTICS_LOW_PRIO"
SET 'USER NAME' = 'NSHARMA';

-- General-purpose checks used throughout this troubleshooting
SELECT * FROM WORKLOAD_CLASSES;
SELECT * FROM WORKLOAD_MAPPINGS;
SELECT SCHEMA_NAME, VIEW_NAME FROM SYS.VIEWS WHERE VIEW_NAME LIKE '%WORKLOAD_MAPPING%';

-- The definitive check: not timing, not the mapping's existence, but the
-- database's own record of how many statements were actually admitted under
-- the class. This is what confirmed the corrected mapping was genuinely
-- governing the session (630 admitted statements, per report Table 10).
SELECT * FROM M_WORKLOAD_CLASS_STATISTICS
WHERE WORKLOAD_CLASS_NAME = 'ANALYTICS_LOW_PRIO';

-- With the corrected mapping active and a fresh session open, the
-- concurrent aggregation from 04_concurrency_mvcc_htap.sql was re-run to
-- produce the governed timing in report Table 9/10.
