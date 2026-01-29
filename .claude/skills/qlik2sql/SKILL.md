---
name: qlik2sql
description: Analyze QlikSense code and translate it to SQL Server (tables, views, stored procedures)
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "[analyze|translate|full] [file path or paste code in chat]"
---

# QlikSense to SQL Server Migration Skill

You are helping migrate QlikSense Apps to SQL Server. The user will provide QlikSense code (either as a file path or pasted directly in chat).

## Workflow

When user invokes `/qlik2sql`, follow these steps in order:

### Step 1: Identify Data Sources

Analyze the QlikSense code and categorize ALL data sources:

| Source Type | How to Identify | Example |
|-------------|-----------------|---------|
| **SQL Server** | `OLEDB CONNECT`, `lib://` with SQL connection | `FROM [lib://DW_Connection/schema.table]` |
| **QVD File** | `.qvd` extension | `FROM [lib://Data/file.qvd] (qvd)` |
| **Excel/CSV** | `.xlsx`, `.xls`, `.csv` extension | `FROM [lib://Data/file.xlsx] (ooxml)` |
| **INLINE Data** | `LOAD * INLINE [...]` | Hardcoded mapping tables |
| **Web Connector** | `lib://` with REST or web path | `FROM [lib://REST_API/endpoint]` |
| **Resident Table** | `RESIDENT TableName` | Data from previously loaded QlikSense table |

**Output format:**
```
## 1. Data Sources

| Source Name | Type | Path/Location | SQL Server Equivalent Needed? |
|-------------|------|---------------|-------------------------------|
| xxx | QVD | lib://... | Yes - need to trace origin |
| xxx | INLINE | (in script) | Yes - create mapping table |
| xxx | SQL Server | lib://... | Already exists |
```

### Step 2: Identify Output

List what the script produces:

```
## 2. Output

| Output Name | Type | Path/Location |
|-------------|------|---------------|
| xxx.qvd | QVD | lib://... |
```

### Step 3: Analyze Dependencies

For QVD sources, note that user needs to:
- Provide the QlikSense script that generates that QVD, OR
- Confirm what SQL Server table/view it maps to

```
## 3. Dependencies to Resolve

| QVD Source | Status | Action Required |
|------------|--------|-----------------|
| xxx.qvd | Unknown | Need source script or SQL mapping |
```

### Step 4: SQL Server Objects Required

List all objects needed to replicate the QlikSense logic:

```
## 4. SQL Server Objects Required

### Mapping Tables (from INLINE data)
| Table Name | Purpose | Columns |
|------------|---------|---------|
| dbo.xxx_Mapping | Map xxx to yyy | RangeStart, RangeEnd, Category |

### Source Tables/Views (dependencies)
| Object Name | Source | Notes |
|-------------|--------|-------|
| dbo.xxx | From QVD xxx.qvd | Need to confirm SQL source |

### Output Objects
| Object Type | Name | Purpose |
|-------------|------|---------|
| View/Table | dbo.vw_xxx | Replaces xxx.qvd output |
| Stored Procedure | dbo.usp_xxx | ETL logic |
```

### Step 5: Generate SQL Code (only when user confirms dependencies)

When user confirms all dependencies are resolved, generate:

1. **Mapping tables** with INSERT statements for INLINE data
2. **Stored Procedure** that replicates the QlikSense transformation logic
3. **View** for the final output (if appropriate)

## QlikSense to SQL Translation Reference

### Common QlikSense Functions → SQL Equivalents

| QlikSense | SQL Server |
|-----------|------------|
| `SubField(field, ',', n)` | `PARSENAME(REPLACE(field, ',', '.'), n)` or STRING_SPLIT |
| `Left(field, n)` | `LEFT(field, n)` |
| `Mid(field, start, len)` | `SUBSTRING(field, start, len)` |
| `Upper(field)` | `UPPER(field)` |
| `Num(field)` | `CAST(field AS INT)` or `TRY_CAST` |
| `Len(Trim(field))` | `LEN(LTRIM(RTRIM(field)))` |
| `IF(condition, true, false)` | `CASE WHEN condition THEN true ELSE false END` |
| `NoConcatenate` | New table (not appending) |
| `LOAD DISTINCT` | `SELECT DISTINCT` |
| `RESIDENT Table` | `FROM dbo.Table` |
| `IntervalMatch` | `BETWEEN` in JOIN or CTE with range logic |
| `Left Join` | `LEFT JOIN` |
| `ApplyMap('MapTable', field, default)` | `LEFT JOIN` + `COALESCE` |

### IntervalMatch Translation Pattern

QlikSense:
```qlik
RangeMap:
LOAD * INLINE [RangeStart, RangeEnd, Category
0, 10, Cat_A
11, 20, Cat_B];

Left Join IntervalMatch (NumField)
LOAD RangeStart, RangeEnd RESIDENT RangeMap;

LEFT JOIN (BaseTable)
LOAD NumField, Category RESIDENT RangeMap;
```

SQL Server:
```sql
-- Create mapping table
CREATE TABLE dbo.RangeMap (
    RangeStart INT,
    RangeEnd INT,
    Category NVARCHAR(100)
);

-- Use in query
SELECT b.*, m.Category
FROM BaseTable b
LEFT JOIN dbo.RangeMap m
    ON b.NumField BETWEEN m.RangeStart AND m.RangeEnd;
```

## Example Usage

```
/qlik2sql analyze                    -- Analyze code in current file or chat
/qlik2sql translate                  -- Generate SQL after dependencies confirmed
/qlik2sql full path/to/file.md       -- Full analysis and translation
```

## Notes

- Always ask user to confirm QVD dependencies before generating final SQL
- Preserve business logic comments from QlikSense code
- Use `TRY_CAST` for safer type conversions
- Consider using CTEs for complex nested LOADs
- For large INLINE tables, suggest separate reference table in SQL Server
