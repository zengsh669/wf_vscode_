---
name: qlik2sql
description: Compare QlikSense code with existing SQL Server objects (SILVER tables/SPs, GOLD views)
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "[file path or paste code in chat]"
---

# QlikSense to SQL Server Comparison Skill

You are helping verify that QlikSense Apps have been correctly migrated to SQL Server. The user will provide QlikSense code (either as a file path or pasted directly in chat), and you will compare it against existing SQL Server objects.

## SQL Server Object Repositories

The existing SQL Server objects are stored in these regularly updated notebooks:

| Database | Object Types | File Location |
|----------|--------------|---------------|
| **SILVER** | Tables, Stored Procedures | `sql_db\DWH_\Database\silver_tbl_sp.ipynb` |
| **GOLD** | Views | `sql_db\DWH_\Database\gold_view.ipynb` |

## Workflow

When user invokes `/qlik2sql`, follow these steps in order:

### Step 1: Analyze QlikSense Code

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
| xxx | QVD | lib://... |

### Output
| Output Name | Type | Path/Location |
|-------------|------|---------------|
| xxx.qvd | QVD | lib://... |
```

### Step 2: Search for Corresponding SQL Objects

Search the notebook files for matching SQL objects:

1. **Search `silver_tbl_sp.ipynb`** for:
   - Tables that match QlikSense output (e.g., `fact_claim_data` for `ClaimEpisodeLink.qvd`)
   - Stored Procedures that replicate the QlikSense logic

2. **Search `gold_view.ipynb`** for:
   - Views that consume SILVER tables or replicate QlikSense output

**Use Grep to search:**
```
Grep pattern="<table_name_or_sp_name>" path="sql_db\DWH_\Database\silver_tbl_sp.ipynb"
Grep pattern="<view_name>" path="sql_db\DWH_\Database\gold_view.ipynb"
```

**Output format:**
```
## 2. SQL Server Objects Found

| QlikSense Output | SQL Object | Type | Location |
|------------------|------------|------|----------|
| ClaimEpisodeLink.qvd | SILVER.dbo.fact_claim_data | Table | silver_tbl_sp.ipynb |
| ClaimEpisodeLink.qvd | SILVER.dbo.sp_LoadFactClaimData | Stored Procedure | silver_tbl_sp.ipynb |
```

### Step 3: Compare Logic

For each matched SQL object, compare:

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
| ClaimDetailGenAndHosp | BRONZE.dbo.ClaimDetailGenAndHosp | ✅ |

### JOIN Logic
| QlikSense | SQL Server | Match? |
|-----------|------------|--------|
| JOIN claim_line ON claim_id, claim_line_id | Same | ✅ |

### Filter Conditions
| Condition | QlikSense | SQL Server | Match? |
|-----------|-----------|------------|--------|
| claim_type filter | IN ('Hospital','Medical') | IN ('Hospital','Medical') | ✅ |

### Calculations
| Calculation | QlikSense | SQL Server | Match? |
|-------------|-----------|------------|--------|
| Key generation | CAST + CONVERT | CAST + CONVERT | ✅ |

### Output Fields
| Field | QlikSense | SQL Server | Match? |
|-------|-----------|------------|--------|
| claim_id | ✅ | ✅ | ✅ |
```

### Step 4: Summary

Provide a final summary:

```
## 4. Summary

| QlikSense Script | SQL Equivalent | Status |
|------------------|----------------|--------|
| xxx.md | SILVER.dbo.sp_xxx → SILVER.dbo.table_xxx | ✅ Fully Matched |
| yyy.md | Not Found | ❌ Needs Migration |

### Discrepancies Found (if any)
- List any logic differences
- List any missing fields
- List any filter condition mismatches
```

## QlikSense to SQL Translation Reference

For understanding logic equivalence:

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
/qlik2sql path/to/script.md    -- Compare QlikSense script with existing SQL objects
/qlik2sql                       -- Compare code pasted in chat
```

## Notes

- Always search BOTH notebook files for complete coverage
- Note schema prefixes (BRONZE.dbo.xxx for source tables)
- ORDER BY differences are acceptable (not meaningful for table inserts)
- CTE vs subquery differences are acceptable (same logic, different syntax)
- Report any logic discrepancies clearly for user review
