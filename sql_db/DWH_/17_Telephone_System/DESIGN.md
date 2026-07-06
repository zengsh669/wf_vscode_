# QMS Telephone System Dashboard — DWH Design

## Overview

Extracts call recording and agent data from the QMS (Quality Management System) into a
SILVER table consumed directly by Power BI for historical analysis of Phone and Chat activity.

**Source systems:**
- QMS SQL database (`BRONZE.qms`) — call recording platform

**Architecture decision:** No GOLD view is built. Power BI imports the single Silver table
directly and computes all measures via DAX.

---

## Architecture

```
BRONZE (read-only)                  SILVER (1 table)               Power BI
──────────────────────────          ────────────────────────────   ─────────────────────
BRONZE.qms.Recording_Details ──→    dbo.QMS_Recording_Detail ──→   fact_QMS_Recording_Detail (PBI) ──→   DAX Measures
BRONZE.qms.User_Details      ──→
```

---

## Silver Tables

### 1. `QMS_Recording_Detail` (Silver) → `fact_QMS_Recording_Detail` (Power BI)

**Granularity:** One row per call recording (Phone or Chat).

**Data sources:**

| Table | Role |
|---|---|
| `BRONZE.qms.Recording_Details` | Call recording base (duration, timestamps, media type) |
| `BRONZE.qms.User_Details` | Agent name and department |

**Filter:**
- `Stop_Date IS NOT NULL` — excludes in-progress recordings
- `Media_Type IN (0, 4)` — 0 = Phone, 4 = Chat
- `Start_Date >= DATEADD(YEAR, -5, CAST(GETDATE() AS date))` — rolling 5-year window

**Key columns:**

| Column | Origin | Notes |
|---|---|---|
| `User_ID` | `User_Details.User_ID` | JOIN key |
| `Agent_Name` | `First_Name + ' ' + Last_Name` | |
| `Department_Name` | `User_Details.Department_Name` | ~94% fill rate; NULL = unknown |
| `Media_Type` | `Recording_Details.Media_Type` | 0 = Phone, 4 = Chat |
| `Recording_ID` | `Recording_Details.Recording_ID` | Unique recording identifier |
| `Start_Date` | `Recording_Details.Start_Date` | Used for date slicing in Power BI |
| `Start_Time` | `Recording_Details.Start_Time` | |
| `Stop_Date` | `Recording_Details.Stop_Date` | Always populated (filtered) |
| `Stop_Time` | `Recording_Details.Stop_Time` | |
| `Duration` | `Recording_Details.Duration` | In seconds; used for Worktime and Handle Time |

**Generated files:**
- `create_table_fact_QMS_Recording_Detail.sql`
- `usp_Load_fact_QMS_Recording_Detail.sql`

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `GOLD.dbo.vw_QMS_Recording` | Single Silver table; Power BI connects directly to Silver — no Gold layer needed |
| `SILVER.dbo.QMS_Flag_Detail` | `Flag_Details.QueueName` has only 79% coverage (432,962 / 548,235 recordings); deferred pending business confirmation on agent grouping logic |
| Daily summary table | Considered but rejected — detail grain gives Power BI full date-range flexibility via DAX |

---

## Investigation Notes

### Source tables considered

| Table | Rows | Used? | Reason |
|---|---|---|---|
| `BRONZE.qms.Recording_Details` | 548,235 | Yes | Core recording data |
| `BRONZE.qms.User_Details` | 303 | Yes | Agent name and department |
| `BRONZE.qms.Flag_Details` | Large | Deferred | QueueName only 79% populated; `Group_Name` in User_Details is 0% populated |
| `BRONZE.qms.Evaluation_Details` | — | No | Scorecard/evaluation data; not relevant to this dashboard |

### Media_Type values confirmed

| Media_Type | Count | Meaning |
|---|---|---|
| 0 | 491,312 | Phone |
| 4 | 56,923 | Chat |
| 11 | 18 | Other (excluded) |

### Agent grouping — unresolved

- `User_Details.Group_Name` — 0% populated (all NULL)
- `User_Details.Department_Name` — 94% populated; values include Care Centre, Sales, Claims, IT, etc.
- `Flag_Details.QueueName` — 79% populated; per-call queue (Members, SALES, Support, etc.)
- The original QMS wallboard shows a label after the agent name (e.g. "Alisha Barrett - Care Centres") — exact source of this label to be confirmed with business

### Grain decision

Two query options were evaluated:

| Option | File | Rows | Notes |
|---|---|---|---|
| Detail (chosen) | `qms_recording_detail.sql` | ~535,790 | One row per call; DAX handles all aggregation |
| Daily summary | `qms_recording_daily_summary.sql` | ~61,000 | Pre-aggregated by agent/day/media; `Total_Logged_In_Seconds` assumes contiguous session per day — inaccurate if agent logs in/out multiple times |

Detail grain was chosen because Power BI date slicers require full flexibility (any date range, not just daily buckets).

### Wallboard measures vs available data

The QMS wallboard (real-time system) shows 7 columns. Investigation confirmed only 3 can be reproduced from `Recording_Details`:

| Wallboard Column | Reproducible | Reason |
|---|---|---|
| Time in this State | ✗ | Real-time agent state; requires live session feed |
| Total Calls | ✓ | `COUNTROWS` |
| Total Logged In Time | ✗ | No login/logout events in source data |
| Total Worktime | ✓ | `SUM(Duration)` |
| Total Break Time | ✗ | Depends on Logged In Time — not available |
| Average Handle Time | ✓ | `AVERAGE(Duration)` |
| Average Talk Time | ✗ | `Duration` cannot be subdivided into Talk vs Hold vs Wrap-up |

**Root cause:** The wallboard is a real-time system with a full agent state machine (login, logout, hold, wrap-up each timed separately). `Recording_Details` only stores call start/stop timestamps — intermediate state detail is lost.

All 4 BRONZE tables (`Recording_Details`, `User_Details`, `Flag_Details`, `Evaluation_Details`) were inspected. None contain Hold Time, Talk Time, or Wrap-up Time as separate fields.

`Duration` = Handle Time (Start → Stop of the entire recording), and cannot be broken down further.

### BRONZE storage

BRONZE originates from ODS. The 5-year rolling window in the SP limits SILVER growth. Whether ODS itself is pruned is an infrastructure decision outside this project's scope — to be confirmed with IT/DBA.

---

## Power BI Data Connection

| Power Query Query Name | Source |
|---|---|
| `fact_QMS_Recording_Detail` | `SILVER.dbo.QMS_Recording_Detail` |

---

## Power BI Report Layout

### Slicers (top of page)
- `Start_Date` — date range picker
- `Media_Type` — Phone (0) / Chat (4) button toggle

### Top — Card Visuals
| Card | DAX Measure |
|---|---|
| Total Calls | `[Total_Calls]` |
| Total Worktime | `[Total_Worktime]` |
| Avg Handle Time | `[Avg_Handle_Time]` |

### Middle — Charts
| Visual | X-axis | Y-axis / Values |
|---|---|---|
| Line chart | `Start_Date` | `[Total_Calls]` |
| Line chart | `Start_Date` | `[Total_Worktime]` |
| Line chart | `Start_Date` | `[Avg_Handle_Time]` |
| Clustered bar | `Department_Name` | `[Total_Calls]` |

### Bottom — Matrix
- **Rows:** `Department_Name` → `Agent_Name`
- **Values:** `[Total_Calls]`, `[Total_Worktime]`, `[Avg_Handle_Time]`

---

## DAX Measures

### Total_Calls
```dax
Total_Calls =
COUNTROWS( fact_QMS_Recording_Detail )
```

### Total_Worktime
```dax
Total_Worktime =
SUM( fact_QMS_Recording_Detail[Duration] )
```

### Avg_Handle_Time
```dax
Avg_Handle_Time =
DIVIDE( [Total_Worktime], [Total_Calls], 0 )
```

> **Note:** `Duration` = Handle Time (full recording Start → Stop). Cannot be subdivided into
> Talk Time, Hold Time, or Wrap-up Time — these are not stored separately in any of the 4 QMS tables.
> `Total_Logged_In_Time`, `Total_Break_Time`, and `Avg_Talk_Time` are not buildable from available data.

### Dynamic Format String Expressions

All time measures return raw seconds. Apply **Dynamic Format String** in Power BI Desktop:
`Modeling → Format → (dropdown) Dynamic → Format string expression`

**For `Total_Worktime`:**
```dax
VAR _TotalTime = SELECTEDMEASURE()
VAR _Hours     = TRUNC( _TotalTime / 3600 )
VAR _Minutes   = TRUNC( MOD( _TotalTime, 3600 ) / 60 )
VAR _Seconds   = MOD( _TotalTime, 60 )
RETURN
    """" &
    FORMAT( _Hours,   "00" ) & ":" &
    FORMAT( _Minutes, "00" ) & ":" &
    FORMAT( _Seconds, "00" ) &
    """"
```

**For `Avg_Handle_Time`** (typically < 1 hour):
```dax
VAR _TotalTime = SELECTEDMEASURE()
VAR _Hours     = TRUNC( _TotalTime / 3600 )
VAR _Minutes   = TRUNC( MOD( _TotalTime, 3600 ) / 60 )
VAR _Seconds   = MOD( _TotalTime, 60 )
RETURN
    """" &
    FORMAT( _Hours,   "00" ) & ":" &
    FORMAT( _Minutes, "00" ) & ":" &
    FORMAT( _Seconds, "00" ) &
    """"
```

---

## Files

```
sql_db/DWH_/17_Telephone_System/
├── DESIGN.md                              ← this file
├── create_table_QMS_Recording_Detail.sql  ← CREATE TABLE for SILVER
├── usp_Load_QMS_Recording_Detail.sql      ← TRUNCATE + INSERT SP, rolling 5-year window
├── qms_recording_detail.sql              ← source query reference (detail grain, ~535k rows)
└── qms_recording_daily_summary.sql       ← alternative pre-aggregated query (daily grain, ~61k rows)
```

---

## ADF Column Mapping Files

These JSON files define the ADF Copy Activity column mappings from `BRONZE.qms` to the
sink dataset. Located in `sql_db/ADF_parametres/`:

| File | Source Table |
|---|---|
| `sql_db/ADF_parametres/tbl_PARAGON_Flag_Details.json` | `BRONZE.qms.Flag_Details` |
| `sql_db/ADF_parametres/tbl_PARAGON_Evaluation_Details.json` | `BRONZE.qms.Evaluation_Details` |
| `sql_db/ADF_parametres/tbl_PARAGON_Recording_Details.json` | `BRONZE.qms.Recording_Details` |
| `sql_db/ADF_parametres/tbl_PARAGON_User_Details.json` | `BRONZE.qms.User_Details` |

**Type mapping reference:**

| SQL Type | ADF `type` | physicalType (sink) |
|---|---|---|
| `uniqueidentifier` | `Guid` | `uniqueidentifier` |
| `nvarchar` | `String` | `nvarchar` |
| `decimal` | `Decimal` | `decimal` |
| `int` | `Int32` | `int` |
| `smallint` | `Int16` | `smallint` |
| `bigint` | `Int64` | `bigint` |
| `tinyint` | `Byte` | `tinyint` |
| `bit` | `Boolean` | `bit` |
| `date` | `DateTime` | `date` |
| `time` | `TimeSpan` | `time` |
| `datetime` | `DateTime` | `datetime2` |

**ADF Pre-copy script** (sink schema is fixed `qms`):
```
@concat('IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[qms].[', item().destination.table, ']'') AND type in (N''U'')) TRUNCATE TABLE [qms].[', item().destination.table, ']')
```

---

## Refresh Strategy

Single SP using `TRUNCATE + INSERT` full refresh pattern.
Rolling 5-year window — older records are automatically excluded on each run.

```
1. usp_Load_fact_QMS_Recording_Detail
```
