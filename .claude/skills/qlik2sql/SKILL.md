---
name: qlik2sql
description: Translate QlikSense code (.md file) into SQL Server objects (CREATE TABLE + Stored Procedure), or verify an existing SQL object is a perfect replication of the Qlik code.
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "[qlik_file.md] [view:xxx | table:xxx | sp:xxx] (SQL object optional — omit to generate SQL from scratch)"
---

# QlikSense to SQL Server Skill

Two modes depending on whether a SQL object is provided:

- **Generate mode** (no SQL object): translate Qlik → `CREATE TABLE` + Stored Procedure in SILVER
- **Verify mode** (SQL object provided): compare Qlik logic vs existing SQL object, report differences

---

## Generate Mode Workflow (no SQL object provided)

### Step 0: Source Table Discovery

1. Read the Qlik `.md` file
2. Extract ALL data sources grouped by type:

**SQL Tables** (from `SQL SELECT ... FROM`):
```
| Table Name | Schema | Database | Role in Script |
|------------|--------|----------|----------------|
| memship    | dbo    | paragonreporting | Main membership table |
```

**QVD Files** (from `FROM [lib://...]`):
```
| File Name | Library | Used As |
|-----------|---------|---------|
| Paragon_Grouping.qvd | ExtractData | GroupMap mapping |
```

**Other Files** (Excel, CSV, etc.):
```
| File Name | Library | Used As |
|-----------|---------|---------|
| Sales Channel Mapping.xlsx | Manual Data | SalesChannelMapping |
```

3. **STOP — ask user to confirm** the source table list before continuing.

---

### Step 1: Confirm Database & Object Mapping

After user confirms, ask the user to clarify:

1. **SQL tables** → which BRONZE table/view they map to (usually same name, different database)
2. **QVD files** → which BRONZE table they correspond to
3. **Views** → identify any tables that are actually views; ask user to provide their SQL code
4. **Excel/CSV files** → confirm if data exists in a DB table, or skip with comment placeholder

**Important rules:**
- `CREATE PROCEDURE` cannot use a database prefix. Use `USE [DB]; GO` before the definition instead.
- QVD mappings (`ApplyMap`) → `LEFT JOIN` to their BRONZE equivalent table
- Excel mappings with no DB equivalent → leave a comment placeholder in the SQL

**STOP — present confirmed mapping table and ask user to approve before continuing.**

---

### Step 2: Identify Nested View Dependencies

For any views provided by the user, check if they reference other views.
Build the full dependency chain (e.g., `ProductPremium` → `MemberProducts` → `CurrentProductFee`).

Ask the user:
> "View X has nested dependencies [list them]. Do you want to:
> A) Inline all layers as CTEs (self-contained, longer)
> B) Reference the existing views directly (simpler, requires views exist in target DB)"

**STOP — wait for user's choice before continuing.**

---

### Step 3: Identify Output Tables & Naming

Each named Qlik LOAD section becomes one output table in SILVER.

Propose table names using the naming convention:
- Each word: first letter uppercase, rest lowercase
- Words separated by `_`
- Examples: `Retained_Member`, `Retention_Tasklist`

**STOP — confirm table names with user before continuing.**

---

### Step 4: Data Type Discovery

Before writing `CREATE TABLE`, identify all columns whose data types are uncertain.
Provide this query for the user to run:

```sql
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE
FROM BRONZE.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN (/* source tables */)
  AND COLUMN_NAME IN (/* uncertain columns */)
ORDER BY TABLE_NAME, COLUMN_NAME;
```

**Rules for derived columns:**
| Qlik / SQL expression | SILVER data type |
|---|---|
| `CAST(datetime AS DATE)` | `DATE` |
| `DATEDIFF(DAY, ...)` | `INT` |
| `FORMAT(date, 'MMM yyyy')` | `VARCHAR(8)` |
| `first_name + ' ' + surname` | `VARCHAR(81)` (40+1+40) |
| `CASE WHEN ... THEN 'Greater than 14 Days'` | `VARCHAR(22)` |
| `MONEY * INT` | `MONEY` |
| Source column `TEXT` (deprecated) | Upgrade to `NVARCHAR(MAX)` |

**STOP — present proposed column definitions table and ask user to confirm before generating files.**

---

### Step 5: Generate CREATE TABLE Files

One file per output table, saved to the same folder as the Qlik `.md` file:
- Filename: `create_table_[Table_Name].sql`
- Target: `SILVER.dbo.[Table_Name]`
- Column naming: same Title_Case_With_Underscores convention

Example:
```sql
CREATE TABLE SILVER.dbo.Retained_Member (
    Membership_Id          DECIMAL(9,0)   NOT NULL,
    First_Name             VARCHAR(40)    NULL,
    ...
);
```

**STOP — ask user to create the tables in SILVER and confirm before generating SPs.**

---

### Step 6: Generate Pure SELECT Queries (optional)

Before writing SPs, optionally generate plain `SELECT` queries (no `CREATE VIEW` or `CREATE PROCEDURE` wrapper) for the user to test in SSMS.

- One `.sql` file per Qlik LOAD section
- Filename: matches the Qlik table name (e.g., `tasklist.sql`, `retained_members.sql`)
- Each Qlik named LOAD section → one query file

**STOP — ask user to confirm query results before generating SPs.**

---

### Step 7: Generate Stored Procedures

One SP per output table:
- Filename: `usp_Load_[Table_Name].sql`
- Target database: SILVER
- Strategy: `TRUNCATE + INSERT` (full refresh)
- Use `USE SILVER; GO` before `CREATE OR ALTER PROCEDURE` (no DB prefix on procedure name)

Structure:
```sql
USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_[Table_Name]
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.[Table_Name];

    WITH
    -- CTEs for nested view dependencies (if Option A chosen in Step 2)
    ...

    INSERT INTO SILVER.dbo.[Table_Name] (col1, col2, ...)
    SELECT ...
    FROM BRONZE.dbo.[source_table]
    ...;

END;
```

**CTE strategy (when inlining views):**
- Only include columns in each CTE that are actually used downstream
- Layer CTEs in dependency order: deepest dependency first
- Comment each CTE with what view it replaces

---

## Verify Mode Workflow (SQL object provided)

### Step 1: Read Both Files

1. Read the Qlik `.md` file
2. Locate and read the SQL file(s) based on user-specified object type:
   - Views: Search in `sql_db/DWH_/**/vw_*.sql` or `gold_view.ipynb`
   - Tables: Search in `sql_db/DWH_/**/` or `silver_tbl_sp.ipynb`
   - SPs: Search in `sql_db/DWH_/**/usp_*.sql` or `silver_tbl_sp.ipynb`

### Step 2: Analyze Qlik Code Structure

| Component | What to Look For |
|-----------|------------------|
| **Mapping Tables** | `Mapping LOAD`, `ApplyMap()` |
| **Data Sources** | QVD files, SQL tables, Excel files |
| **JOIN Logic** | `Left Join`, `Inner Join`, `Join` |
| **Filters** | `WHERE` conditions |
| **Calculated Fields** | `If()`, `Wildmatch()`, `Match()`, `ApplyMap()` |
| **Interval Matching** | `IntervalMatch` for cohort grouping |
| **Resident Loads** | `RESIDENT TableName` |
| **Inline Tables** | `LOAD * INLINE [...]` |

### Step 3: Analyze SQL Code Structure

| Component | What to Look For |
|-----------|------------------|
| **CTEs** | `WITH ... AS` (equivalent to Qlik mapping tables) |
| **JOINs** | `LEFT JOIN`, `INNER JOIN` |
| **Filters** | `WHERE` clauses, JOIN conditions |
| **Calculated Fields** | `CASE WHEN`, `IIF()` |
| **Interval Matching** | `BETWEEN` in JOIN conditions |

### Step 4: Compare Logic

#### Table/Data Source Mapping
```
| Purpose | Qlik Source | SQL Source |
|---------|-------------|------------|
| Memberships | Paragon_Memberships.qvd | BRONZE.dbo.memship |
```

#### JOIN Logic
| Qlik JOIN | Qlik Keys | SQL JOIN | SQL Keys | Match? |
|-----------|-----------|----------|----------|--------|
| `Left Join (Claims)` | person_id | `LEFT JOIN` | person_id | ? |

**Important:** Qlik auto-joins on ALL matching field names. Verify SQL includes all keys.

#### Filter Conditions
| Filter | Qlik | SQL | Match? |
|--------|------|-----|--------|
| Status filter | `WHERE status = 'X'` | `WHERE status = 'X'` | ? |

### Step 5: Identify Differences

**Critical (Affects Data):** Missing JOINs, wrong JOIN keys, missing filters, incorrect business logic

**Non-Critical (Acceptable):** Date format differences, ORDER BY, CTE vs subquery, column alias differences

**Missing Features:** Calendar dimensions, Excel mappings, Set Analysis

### Step 6: Verification Queries

```sql
-- Check if key is unique (for JOIN validation)
SELECT column_name, COUNT(*)
FROM table_name
GROUP BY column_name
HAVING COUNT(*) > 1;

-- Check column exists in source table
SELECT COLUMN_NAME, DATA_TYPE
FROM BRONZE.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'table_name'
  AND COLUMN_NAME LIKE '%pattern%';
```

### Step 7: Final Summary

```
## Summary

### Replication Status: [100% | XX%]

| Category | Completion |
|----------|------------|
| Core Data Logic | XX% |
| JOIN Logic | XX% |
| Business Calculations | XX% |
| Output Fields | XX% |

### Items Requiring Action
| # | Issue | Severity | Recommendation |
|---|-------|----------|----------------|
| 1 | Missing Sales Channel Group mapping | Low | Import Excel to DB |
```

---

## QlikSense to SQL Translation Reference

| QlikSense | SQL Server |
|-----------|------------|
| `ApplyMap('Map', field, default)` | `LEFT JOIN` + `ISNULL(col, default)` |
| `Wildmatch(field, '*pattern*')` | `field LIKE '%pattern%'` |
| `Wildmatch(field, 'A','B','C')` | `field IN ('A','B','C')` |
| `Wildmatch(field, 'A*')` | `field LIKE 'A%'` |
| `Match(field, 'A','B')` | `field IN ('A','B')` |
| `If(cond, true, false)` | `CASE WHEN cond THEN true ELSE false END` |
| `if(isnull(field), 'default', field)` | `ISNULL(field, 'default')` |
| `IntervalMatch` | `BETWEEN` in JOIN |
| `Age(date1, date2)` | `DATEDIFF(YEAR,...) - CASE WHEN...` |
| `Monthname(date)` | `FORMAT(date, 'MMM yyyy')` |
| `WeekEnd(date)` (FirstWeekDay=6, week ends Saturday) | `DATEADD(DAY, 6 - (DATEDIFF(DAY, '1900-01-07', date) % 7), date)` |
| `today() - date` | `DATEDIFF(DAY, date, CAST(GETDATE() AS DATE))` |
| `Left Join (Table)` | `LEFT JOIN` (check all matching field names!) |
| `Join (Table)` | `INNER JOIN` |
| `RESIDENT Table` | Reference to CTE or temp table |
| `NoConcatenate` | New result set (not UNION) |

## General Notes

- Never use a database prefix on `CREATE PROCEDURE` — use `USE [DB]; GO` before the definition
- Qlik `Left Join` auto-matches on ALL fields with same name — verify SQL includes all keys
- `TEXT` columns from source → upgrade to `NVARCHAR(MAX)` in SILVER
- Excel/CSV mappings with no DB equivalent → leave comment placeholder, suggest importing to lookup table
- Always confirm with user at each STOP point before proceeding to the next step
- QVD files always have a corresponding BRONZE table — ask user for the mapping if unclear
