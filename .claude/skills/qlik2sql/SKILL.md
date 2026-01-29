---
name: qlik2sql
description: Compare QlikSense code (in .md file) with SQL Server objects to verify perfect replication
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "[qlik_file.md] [view:xxx | table:xxx | sp:xxx]"
---

# QlikSense to SQL Server Comparison Skill

You are helping verify that QlikSense code has been correctly migrated to SQL Server. Compare the QlikSense code logic with SQL objects to determine if the SQL is a **perfect replication** of the Qlik code.

## User Input

User will provide:
1. **QlikSense code file** - a `.md` file containing Qlik script
2. **SQL object type and name** - one or more of:
   - `view:object_name` - SQL View
   - `table:object_name` - SQL Table
   - `sp:object_name` - Stored Procedure

**Example:**
```
/qlik2sql sql_db/DWH_/07_Claim_Dashboard_HCS/cla_dash_hcs.md view:vw_HCS_Claims
```

## Workflow

### Step 1: Read Both Files

1. Read the Qlik `.md` file
2. Locate and read the SQL file(s) based on user-specified object type:
   - Views: Search in `sql_db/DWH_/**/vw_*.sql` or `gold_view.ipynb`
   - Tables: Search in `sql_db/DWH_/**/` or `silver_tbl_sp.ipynb`
   - SPs: Search in `sql_db/DWH_/**/usp_*.sql` or `silver_tbl_sp.ipynb`

### Step 2: Analyze Qlik Code Structure

Identify these components from the Qlik script:

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

Identify these components from the SQL:

| Component | What to Look For |
|-----------|------------------|
| **CTEs** | `WITH ... AS` (equivalent to Qlik mapping tables) |
| **JOINs** | `LEFT JOIN`, `INNER JOIN` |
| **Filters** | `WHERE` clauses, JOIN conditions |
| **Calculated Fields** | `CASE WHEN`, `IIF()` |
| **Interval Matching** | `BETWEEN` in JOIN conditions |

### Step 4: Compare Logic - Detailed Checklist

#### 4.1 Table/Data Source Mapping

Create a complete table mapping:

```
## Table Mapping

### Mapping Tables
| Purpose | Qlik Source | SQL Source |
|---------|-------------|------------|
| Item Description | paragonreporting.dbo.item | BRONZE.dbo.item |

### Core Business Tables
| Purpose | Qlik Source | SQL Source |
|---------|-------------|------------|
| Memberships | Paragon_Memberships.qvd | BRONZE.dbo.memship |

### Derived/Generated Tables
| Purpose | Qlik Source | SQL Source |
|---------|-------------|------------|
| Age Cohorts | Inline definition | CTE definition |
| MasterCalendar | Dynamic generation | (missing/separate view) |
```

#### 4.2 JOIN Logic Comparison

For each JOIN in Qlik, verify SQL equivalent:

| Qlik JOIN | Qlik Keys | SQL JOIN | SQL Keys | Match? |
|-----------|-----------|----------|----------|--------|
| `Left Join (Claims)` | person_id | `LEFT JOIN` | person_id | ? |

**Important:** Qlik auto-joins on ALL matching field names. Verify SQL includes all necessary keys.

#### 4.3 Business Logic Comparison

For complex calculated fields (e.g., Product Group, Hospital Tier):

```
### Product Group Logic
Qlik (line XX):
If(Wildmatch("field", 'A','B'), 'Result1', ...)

SQL (line XX):
CASE WHEN field IN ('A','B') THEN 'Result1' ... END

Match: Yes/No
```

#### 4.4 Filter Conditions

| Filter | Qlik | SQL | Match? |
|--------|------|-----|--------|
| Paid claims only | `WHERE line_status = 'Paid'` | `WHERE line_status = 'Paid'` | ? |
| Date filter | `service_date > '01/01/2021'` | `service_date > '2021-01-01'` | ? |

### Step 5: Identify Differences

Categorize any differences found:

#### Critical (Affects Data)
- Missing JOINs
- Wrong JOIN keys
- Missing filter conditions
- Incorrect business logic

#### Non-Critical (Acceptable)
- Date format differences (can be ignored if user specifies)
- ORDER BY differences
- CTE vs subquery (same logic, different syntax)
- Column alias differences

#### Missing Features (May Need Separate Implementation)
- Calendar dimension tables
- Geographic mapping from Excel files
- Set Analysis / As-Of Calendar

### Step 6: Verification Queries

Provide SQL queries to verify potential issues:

```sql
-- Check if key is unique (for JOIN validation)
SELECT column_name, COUNT(*)
FROM table_name
GROUP BY column_name
HAVING COUNT(*) > 1;

-- Check field name in source table
SELECT COLUMN_NAME
FROM DATABASE.INFORMATION_SCHEMA.COLUMNS
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
| 1 | Missing SA Level mapping | Low | Import Excel to DB |

### Conclusion
[Statement on whether SQL is a perfect replication of Qlik code]
```

## QlikSense to SQL Translation Reference

| QlikSense | SQL Server |
|-----------|------------|
| `ApplyMap('Map', field, default)` | `LEFT JOIN` + `ISNULL(col, default)` |
| `Wildmatch(field, '*pattern*')` | `field LIKE '%pattern%'` |
| `Wildmatch(field, 'A','B','C')` | `field IN ('A','B','C')` |
| `Wildmatch(field, 'A*')` | `field LIKE 'A%'` |
| `Match(field, 'A','B')` | `field IN ('A','B')` |
| `If(cond, true, false)` | `CASE WHEN cond THEN true ELSE false END` |
| `IntervalMatch` | `BETWEEN` in JOIN |
| `Age(date1, date2)` | `DATEDIFF(YEAR,...) - CASE WHEN...` |
| `Monthname(date)` | `FORMAT(date, 'MMM yyyy')` |
| `Left Join (Table)` | `LEFT JOIN` (check all matching field names!) |
| `Join (Table)` | `INNER JOIN` |
| `RESIDENT Table` | Reference to CTE or temp table |
| `NoConcatenate` | New result set (not UNION) |

## Notes

- Qlik `Left Join` auto-matches on ALL fields with same name - verify SQL includes all keys
- Date format differences are usually acceptable (focus on logic, not format)
- Missing calendar/dimension tables may be implemented separately
- Always provide verification queries for potential issues
