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

## Core Principles (Generate Mode)

These principles apply throughout the entire Generate mode workflow:

### Principle 1 — Faithfulness to Qlik Logic
- All generated SQL must faithfully replicate the source Qlik logic as closely as possible
- Structural flexibility is allowed (e.g. splitting one large Qlik table into multiple smaller Silver tables joined via queries or Power BI model), but the Qlik logic remains the source of truth
- If any part of the Qlik logic appears incorrect, redundant, overly complex, or inefficient, **do not silently fix it** — present the issue and a proposed optimisation to the user and wait for confirmation before applying any change

### Principle 2 — SQL Must Be Runnable
- All generated SQL files must be executable in SQL Server (SSMS) without errors
- Before writing any final SQL file, perform a quality check covering:
  - **Syntax**: brackets, keywords, semicolons, GO statements, USE statements
  - **Business logic**: JOIN conditions and keys, data type compatibility, NULL handling, column references, TRUNCATE + INSERT column alignment

### Principle 3 — Self-Review Before Final Output
- Before writing final SQL files to disk, ask the user:
  > "Do you want me to run a deep review using a sub-agent (recommended for complex scripts)? This will independently audit the SQL for Principle 1 and Principle 2 compliance before output."
- If user confirms: spawn a sub-agent using the `opus` model to independently review the generated SQL against both principles, report findings, and apply any fixes before final output
- If user declines: proceed with self-review only (re-read and verify the generated SQL against both principles before writing files)

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

If there are multiple output tables, also propose a file organisation strategy:
- **Option A: One file per table** — `create_table_X.sql` + `usp_Load_X.sql` for each table (recommended when tables are independent)
- **Option B: Combined files** — all `CREATE TABLE` in one file, all SPs in one file (recommended when tables are tightly related)

**STOP — confirm table names and file organisation with user before continuing.**

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

### Step 4.5: Generate DESIGN.md (write to disk)

Using all confirmed decisions from Step 0–4, generate a `DESIGN.md` file and save it to the same folder as the Qlik `.md` file.

Follow the structure and format of the reference sample at `.claude/skills/qlik2sql/samples/DESIGN.md`. The document must include:
- **Overview** — project summary, source systems, architecture decision (e.g. no GOLD view)
- **Architecture diagram** — ASCII showing data flow from source → SILVER → consumer
- **Silver Tables** — one section per table with: source values, data sources table, key columns table (column / origin / notes), generated files list
- **Objects NOT Built** — any Qlik objects deliberately excluded and why
- **Files to Generate** — full file tree of all `.sql` files to be produced
- **Refresh Strategy** — TRUNCATE + INSERT pattern, recommended SP execution order

**STOP — ask user to review DESIGN.md and confirm before drafting any SQL.**

---

### Step 5: Draft CREATE TABLE SQL (in memory only — do not write files yet)

Draft the CREATE TABLE SQL for each output table in memory:
- Target: `SILVER.dbo.[Table_Name]`
- Column naming: Title_Case_With_Underscores convention

Example draft:
```sql
CREATE TABLE SILVER.dbo.Retained_Member (
    Membership_Id          DECIMAL(9,0)   NOT NULL,
    First_Name             VARCHAR(40)    NULL,
    ...
);
```

**STOP — show draft to user and ask them to confirm column definitions before continuing.**

---

### Step 6: Draft Pure SELECT Queries (optional, in memory only)

Optionally draft plain `SELECT` queries (no SP wrapper) for the user to test in SSMS:
- One query per Qlik LOAD section
- Show the draft queries in the chat for user to copy and run in SSMS

**STOP — ask user to confirm query results before drafting SPs.**

---

### Step 7: Draft Stored Procedures (in memory only — do not write files yet)

Draft the SP SQL for each output table in memory:
- Target database: SILVER
- Strategy: `TRUNCATE + INSERT` (full refresh)
- Use `USE SILVER; GO` before `CREATE OR ALTER PROCEDURE` (no DB prefix on procedure name)

Example draft:
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

### Step 8: Code Quality Check (against in-memory drafts — do not write files yet)

Review all drafted SQL (from Step 5 and Step 7) against **both principles**. Apply checks according to the file organisation strategy confirmed in Step 3 (Option A: one file per table, or Option B: combined files). Apply the following fix rules when issues are found, then re-run the entire Step 8 checklist from the top — repeat until all checks pass before proceeding to Step 9.

**Fix rules:**
- **Pure technical errors** (syntax, mismatched brackets, wrong column count, missing GO, etc.) → Claude fixes automatically without asking the user
- **Business logic issues** (wrong JOIN keys, incorrect filter, unfaithful Qlik translation, data type mismatch that affects output) → present the issue and proposed fix to the user via a STOP, apply only after user confirms

**Principle 1 — Qlik faithfulness checks (re-read the Qlik `.md` source for each item):**
- [ ] Every Qlik LOAD section has a corresponding SQL output table
- [ ] Every Qlik data source (QVD, SQL table, Excel) is accounted for in the SQL (as BRONZE JOIN, CTE, or comment placeholder)
- [ ] Every Qlik `ApplyMap()` is translated as a `LEFT JOIN` + `ISNULL()` with the correct default value
- [ ] Every Qlik `Left Join` includes ALL matching field names as JOIN keys (not just one)
- [ ] Every Qlik filter (`WHERE`, `IF`, `Wildmatch`) has a corresponding SQL equivalent
- [ ] Every Qlik calculated field (`If()`, `Age()`, `Monthname()`, etc.) is correctly translated per the translation reference table
- [ ] If structural flexibility was applied (e.g. one Qlik table split into multiple Silver tables), verify the combined output still reproduces the Qlik logic faithfully
- [ ] Any optimisations applied were explicitly confirmed by the user in an earlier STOP

**Principle 2 — Runnability checks (SQL must execute without errors in SSMS):**
- [ ] All `CREATE TABLE` / `CREATE OR ALTER PROCEDURE` statements are well-formed
- [ ] Brackets are balanced; all strings are properly quoted
- [ ] `USE SILVER; GO` present before every `CREATE OR ALTER PROCEDURE`
- [ ] No database prefix on procedure names
- [ ] All CTEs are properly terminated with commas (except the last)
- [ ] `INSERT INTO` column list matches `SELECT` column count and order
- [ ] `TRUNCATE TABLE` targets the correct table
- [ ] Every JOIN has explicit ON conditions covering all required keys
- [ ] Data types in `INSERT INTO` are compatible with source `SELECT` expressions
- [ ] NULL handling is consistent with Qlik source logic (`ISNULL`, `COALESCE`)
- [ ] All columns referenced in SELECT exist in their source tables (based on Step 4 discovery)
- [ ] `TRUNCATE + INSERT` pattern is complete — no orphaned TRUNCATE without a following INSERT

---

### Step 9: Sub-Agent Independent Review

Ask the user:
> "Step 8 quality check passed. Do you want me to run an independent sub-agent review before writing the final files? The sub-agent will re-run the full Step 8 checklist independently using a stronger model. Recommended for complex scripts."

- **If yes**: spawn a sub-agent with model `opus` — provide it the Qlik `.md` source and all drafted SQL, instruct it to re-run the complete Step 8 checklist (both Principle 1 and Principle 2 checks) independently. If it finds issues, fix the drafts and the sub-agent re-verifies until all checks pass. Then write final SQL files according to the file organisation strategy confirmed in Step 3 (Option A or B).
- **If no**: write final SQL files immediately according to the file organisation strategy confirmed in Step 3 (Option A or B).

**After writing final SQL files (both paths):** Update `DESIGN.md` to reflect any design changes that occurred during Step 5–9 (e.g. column type corrections, logic adjustments, structural changes confirmed by user). The final `DESIGN.md` must be fully consistent with the generated SQL files.

---

## Verify Mode Workflow (SQL object provided)

### Step 1: Read Both Files

1. Read the Qlik `.md` file
2. Locate and read the SQL object from the master notebooks:
   - Views: `sql_db/DWH_/Database/gold_view.ipynb`
   - Tables: `sql_db/DWH_/Database/silver_tbl_sp.ipynb`
   - SPs: `sql_db/DWH_/Database/silver_tbl_sp.ipynb`

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
