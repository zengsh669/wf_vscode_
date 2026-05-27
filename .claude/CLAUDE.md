# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a data engineering workspace for Westfund (a private health insurer). Work centres on translating QlikSense analytics into a SQL Server data warehouse (BRONZE → SILVER → GOLD architecture), validating data migrations, and automating reporting tasks via Jupyter notebooks.

## Repository Structure

```
sql_db/
  DWH_/               # Data warehouse objects, grouped by numbered project
    Database/         # Master notebooks: gold_view.ipynb, silver_tbl_sp.ipynb
                      # Lineage diagrams: data_lineage.html, data_lineage_table.html
    01–12, 66/        # Per-project folders: Qlik .md scripts, .sql files
  Lib_Westfund/       # Shared Python library (Logger, compare_datasets)
  ADF_parametres/     # Azure Data Factory parameter JSON files
  *.ipynb             # Ad-hoc analysis and data validation notebooks
lifecycle_scripts/    # ML lifecycle prediction scripts
old_analysis/         # Archived analysis notebooks
```

## Data Warehouse Architecture

Three-layer SQL Server architecture:

- **BRONZE** — raw source tables from Paragon (the core system), read-only
- **SILVER** — transformed tables loaded by Stored Procedures (TRUNCATE + INSERT full refresh pattern)
- **GOLD** — views that join/aggregate Silver tables for reporting

Key naming conventions:
- Silver tables: `Title_Case_With_Underscores` (e.g., `Retained_Member`)
- Stored procedures: `usp_Load_[Table_Name]` or `sp_Load[TableName]`
- Gold views: `vw_[Name]` for new views; legacy views have no prefix
- SQL files: `create_table_[Name].sql` and `usp_Load_[Name].sql` in the same project folder

**Important SQL rule**: `CREATE PROCEDURE` cannot use a database prefix — always use `USE SILVER; GO` before the procedure definition.

## Skills (Slash Commands)

### `/qlik2sql [qlik_file.md] [view:xxx | table:xxx | sp:xxx]`
Translates QlikSense load scripts into SQL Server objects. Two modes:
- **Generate mode** (no SQL object): multi-step workflow with STOP confirmations at each stage (source discovery → column types → CREATE TABLE → SP)
- **Verify mode** (SQL object provided): compares Qlik logic against existing SQL, reports gaps

### `/lineage [add|remove|update|hcs_claims|full] [details]`
Manages the DWH lineage diagram. Key files:
- [sql_db/DWH_/Database/data_lineage.html](sql_db/DWH_/Database/data_lineage.html) — Mermaid.js flow diagram
- [sql_db/DWH_/Database/data_lineage_table.html](sql_db/DWH_/Database/data_lineage_table.html) — tabular view
- Always update BOTH HTML files and the SKILL.md object lists together

### `/dwh_diff [HEAD~N]`
Compares `gold_view.ipynb` and `silver_tbl_sp.ipynb` between the last two git commits. Reports:
- **新增** — objects added since the previous commit (name only)
- **删除** — objects removed since the previous commit (name only)
- **修改** — objects with SQL changes, shown as clean `- / +` line diffs (whitespace-only changes ignored)

Optional argument `HEAD~N` to compare against an earlier commit.

### `/memship_qlik_usage`
Generates interactive HTML sparkline reports from QlikSense session log exports (Excel/CSV).

### `/copilot-kb [view_name]`
Builds a Copilot Agent Knowledge Base MD file for a `GOLD.copilot` view. Reads the canonical sample at `.claude/skills/copilot-kb/samples/ME_Total_Membership.md` for structure reference, then guides through data refresh, granularity verification, column documentation, and example query generation. Output path defaults to `sql_db/<view_name>.md`.

### `/md2pdf [path/to/file.md]`
Converts a Markdown file to a styled PDF using Word COM. Defaults to `sql_db/title_change_request.md` if no path is given. The source MD file is never modified; the PDF is written to the same directory with the same basename.

## Python Library (`sql_db/Lib_Westfund/`)

Used in notebooks for data validation:

```python
from sql_db.Lib_Westfund import Logger, compare_columns, compare_content, test_joins
```

- `Logger` — wrapper with `debug()`, `warning()`, `error()` methods and severity-based log collection
- `compare_columns(logger, old_df, new_df)` — checks column sets match
- `compare_content(logger, old_df, new_df, pkey, date_fields, datetime_fields, dayfirst, tolerances)` — row-by-row field comparison with numeric tolerance support
- `test_joins(logger, old_df, new_df, pkey)` — checks for keys present in one dataset but not the other
- `run_comparison(...)` — orchestrates all of the above

## QlikSense → SQL Translation Reference

| QlikSense | SQL Server |
|-----------|------------|
| `ApplyMap('Map', field, default)` | `LEFT JOIN` + `ISNULL(col, default)` |
| `Wildmatch(field, '*x*')` | `field LIKE '%x%'` |
| `Match(field, 'A','B')` | `field IN ('A','B')` |
| `If(cond, true, false)` | `CASE WHEN cond THEN true ELSE false END` |
| `IntervalMatch` | `BETWEEN` in JOIN condition |
| `Age(date1, date2)` | `DATEDIFF(YEAR,...)` with month/day adjustment |
| `Monthname(date)` | `FORMAT(date, 'MMM yyyy')` |
| `Left Join (Table)` | `LEFT JOIN` — Qlik auto-matches all same-name fields; verify SQL includes **all** keys |
| `Join (Table)` | `INNER JOIN` |
| `RESIDENT Table` | CTE or temp table reference |
| `NoConcatenate` | Separate result set (not UNION) |

QVD files always have a corresponding BRONZE table. `TEXT` columns from source should be upgraded to `NVARCHAR(MAX)` in SILVER.

## Notebooks

Notebooks connect to SQL Server via `pyodbc` (server: `rpsqlrp01`, database: `paragonreporting`). Key notebooks at root of `sql_db/`:
- `Jira_api_fetch.ipynb` — fetches Jira issues via REST API
- `qvd_converter.ipynb` — converts QVD files to SQL/parquet
- `earned_contributions_rolling.ipynb` — rolling earned contributions calculations
- `Weekly_LHC_Daily_Movement*.ipynb` — LHC (Lifetime Health Cover) daily movement reporting

## Git Notes

`sql_db/DWH_*` is gitignored by default (the wildcard pattern). Only specific notebooks and the `Lib_Westfund/` library are tracked.
