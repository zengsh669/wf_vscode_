---
name: qlik2sql
description: Compare QlikSense code with user-specified SQL Server objects (SILVER tables/SPs, GOLD views)
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "[file path] [table:xxx] [sp:xxx] [view:xxx]"
---

# QlikSense to SQL Server Comparison Skill

You are helping verify that QlikSense Apps have been correctly migrated to SQL Server. The user will provide:
1. QlikSense code (file path or pasted in chat)
2. Related SQL object names to compare against

## SQL Server Object Repositories

| Database | Object Types | File Location |
|----------|--------------|---------------|
| **SILVER** | Tables, Stored Procedures | `sql_db\DWH_\Database\silver_tbl_sp.ipynb` |
| **GOLD** | Views | `sql_db\DWH_\Database\gold_view.ipynb` |

## Workflow

### Step 1: Get User Input

Ask the user to provide:
1. **QlikSense code** - file path or paste in chat
2. **Related SQL objects** - specify which objects to compare:
   - `table:object_name` - SILVER table
   - `sp:object_name` - SILVER stored procedure
   - `view:object_name` - GOLD view

**Example user input:**
```
/qlik2sql sql_db/DWH_/03_Clinical.../script.md table:episode_condition_group sp:usp_generate_episode_condition_group
```

Or user can provide objects in follow-up message:
```
table: episode_condition_group, fact_claim_data
sp: usp_generate_episode_condition_group
view: vw_claim_summary
```

### Step 2: Analyze QlikSense Code

Identify from the QlikSense code:

**Data Sources:**
| Source Type | How to Identify | Example |
|-------------|-----------------|---------|
| **SQL Server** | `OLEDB CONNECT`, `lib://` with SQL connection | `FROM [lib://DW_Connection/schema.table]` |
| **QVD File** | `.qvd` extension | `FROM [lib://Data/file.qvd] (qvd)` |
| **Excel/CSV** | `.xlsx`, `.xls`, `.csv` extension | `FROM [lib://Data/file.xlsx] (ooxml)` |
| **INLINE Data** | `LOAD * INLINE [...]` | Hardcoded mapping tables |
| **Resident Table** | `RESIDENT TableName` | Data from previously loaded QlikSense table |

**Output format:**
```
## 1. QlikSense Analysis

### Data Sources
| Source Name | Type | Path/Location |
|-------------|------|---------------|
| xxx | SQL Server | lib://... |

### Output
| Output Name | Type | Path/Location |
|-------------|------|---------------|
| xxx.qvd | QVD | lib://... |
```

### Step 3: Extract Specified SQL Objects

**IMPORTANT:** Only extract the objects specified by the user. Do NOT scan the entire notebook.

Use this bash command to extract specific objects from notebooks:

```bash
# For SILVER tables/SPs - extract cells containing the object name
sed 's/},{/}\n{/g' "sql_db/DWH_/Database/silver_tbl_sp.ipynb" | grep -i "<object_name>"

# For GOLD views - extract cells containing the object name
sed 's/},{/}\n{/g' "sql_db/DWH_/Database/gold_view.ipynb" | grep -i "<object_name>"
```

**Output format:**
```
## 2. SQL Server Objects

### Table: [dbo].[object_name]
[extracted CREATE TABLE definition]

### Stored Procedure: [dbo].[sp_name]
[extracted CREATE PROCEDURE definition]

### View: [dbo].[view_name]
[extracted CREATE VIEW definition]
```

### Step 4: Compare Logic

For each SQL object, compare with QlikSense:

| Comparison Item | What to Check |
|-----------------|---------------|
| **Source Tables** | Are the same tables/views being queried? |
| **JOIN Logic** | Are JOINs identical (type, conditions)? |
| **Filter Conditions** | Are WHERE clauses matching? |
| **Calculations** | Are computed columns using equivalent logic? |
| **Output Fields** | Do output columns match? |
| **Aggregations** | Are GROUP BY and aggregations the same? |

**Output format:**
```
## 3. Logic Comparison

### Source Tables
| QlikSense | SQL Server | Match? |
|-----------|------------|--------|
| xxx.qvd | BRONZE.dbo.xxx | ✅ |

### Calculations
| Calculation | QlikSense | SQL Server | Match? |
|-------------|-----------|------------|--------|
| Key generation | CAST + CONVERT | CAST + CONVERT | ✅ |

### Output Fields
| Field | QlikSense | SQL Server | Match? |
|-------|-----------|------------|--------|
| claim_id | ✅ | ✅ | ✅ |
```

### Step 5: Summary

```
## 4. Summary

| QlikSense Script | SQL Equivalent | Status |
|------------------|----------------|--------|
| xxx.md | SILVER.dbo.sp_xxx → SILVER.dbo.table_xxx | ✅ Fully Matched |

### Discrepancies Found (if any)
- List any logic differences
- List any missing fields
```

## QlikSense to SQL Translation Reference

| QlikSense | SQL Server |
|-----------|------------|
| `SubField(field, ',', n)` | `PARSENAME(REPLACE(field, ',', '.'), n)` or STRING_SPLIT |
| `Left(field, n)` | `LEFT(field, n)` |
| `Mid(field, start, len)` | `SUBSTRING(field, start, len)` |
| `Upper(field)` | `UPPER(field)` |
| `Num(field)` | `CAST(field AS INT)` or `TRY_CAST` |
| `IF(condition, true, false)` | `CASE WHEN condition THEN true ELSE false END` |
| `NoConcatenate` | New table (not appending) |
| `LOAD DISTINCT` | `SELECT DISTINCT` |
| `RESIDENT Table` | `FROM dbo.Table` |
| `IntervalMatch` | `BETWEEN` in JOIN |
| `ApplyMap('MapTable', field, default)` | `LEFT JOIN` + `COALESCE` |

## Example Usage

```
# Specify objects inline
/qlik2sql path/to/script.md table:fact_claim sp:usp_load_claim

# Or provide objects in follow-up
/qlik2sql path/to/script.md
> table: episode_condition_group
> sp: usp_generate_episode_condition_group
```

## Notes

- Only extract objects specified by the user
- Schema prefix is typically `BRONZE.dbo.xxx` for source, `SILVER.dbo.xxx` for target
- ORDER BY differences are acceptable
- CTE vs subquery differences are acceptable (same logic, different syntax)
