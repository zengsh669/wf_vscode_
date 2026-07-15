# Dental Financial Detail (AccPac GL) — DWH Design

## Overview

Translates the QlikSense QVD-generation script `Finance_Dashboard.md` into a SQL Server
SILVER layer table. This script reads AccPac GL (general ledger) data and produces the
`DentalFinancialDetail.qvd` file consumed by the main `Dental_Centre_Financial_Dashboard.md`
script (as the `Actual` + `Budget` GL journal source for `Dental_Financial_Actual`).

**Source system:**
- AccPac GL — Westfund's general ledger accounting system, landed in SQL Server as
  `BRONZE.sag.*` (schema `sag` created for this project; tables named after their AccPac
  internal file IDs, e.g. `GLPOST`, `GLAFS`, `GLAMF`, `GLASV`)

**Scope decision:** The source Qlik script (`Finance_Dashboard.md`) produces **three** QVD
outputs from the same `Journals`/`GLStructure` base tables — `DentalDetail` (Dental division),
`MedicareRevenue`, and `CostofGoods` (both Eyewear division). Only the **`DentalDetail` →
`DentalFinancialDetail.qvd`** lineage is in scope for this project; `MedicareRevenue` and
`CostofGoods` belong to the unrelated Eyewear reporting suite and are NOT translated here.

**Architecture decision:** No GOLD view. The output Silver table (`Dental_Financial_Detail`)
is consumed directly by the main Dental Centre Financial Dashboard Silver layer
(`Dental_Financial_Actual`, filtered `WHERE Source = 'Actual'`) — see
`sql_db/DWH_/15_Dental_Centre_Financial_Dashboard/DESIGN.md`. The `Finance P&L Mapping.xlsx`
(Level1/2/3/Report layout) is intentionally **not** translated to SQL — it stays as a direct
Power BI / Power Query connection at dashboard-build time.

---

## Architecture

```
BRONZE (read-only, schema: sag)      SILVER                          Consumer
──────────────────────────────       ────────────────────────────    ──────────────────
sag.GLASV (AccPac_GL_Segments) ──┐
sag.GLAMF (AccPac_GL_Accounts)  ─┼──→  Dental_Financial_Detail  ──→  Dental_Financial_Actual
sag.GLPOST (AccPac_GL_Post)     ─┤     (Actual + Budget rows,        (main Dashboard Silver,
sag.GLAFS (AccPac_GL_Budget)    ─┘      Dental division only)         Source='Actual' rows)

Finance P&L Mapping.xlsx ──────────────────────────────────────→  Power BI (direct connect,
                                                                     not translated to SQL)
```

---

## Data Source Mapping

| 数据源类型 | 源表 (AccPac 内部名) | → BRONZE 表 | Role |
|---|---|---|---|
| AccPac GL | Segments | `sag.GLASV` | Segment2/3/5/6/7/9_Map (Company/Division/State/Branch/Product/Cover/HO Dept lookups) |
| AccPac GL | Accounts | `sag.GLAMF` | `AcctType_Map` + `GLStructure` (GL account master, incl. 10-segment account code) |
| AccPac GL | GL Post (journals) | `sag.GLPOST` | `Journals` — Actual GL entries, filtered `AcctType = 'I'` (Income Statement only) |
| AccPac GL | GL Budget | `sag.GLAFS` | `Journals` — Budget entries, unpivoted from 12 monthly columns via CrossTable |

**Excluded from BRONZE/SILVER scope** (per confirmed decisions):
- `AccPac_GLACCGRP` (`AccountGrp_Map`) — feeds `GLStructure.[Account Group]`, which is never
  selected into the final `DentalDetail` output (dead column past `GLStructure`) — skipped entirely
- `Finance P&L Mapping.xlsx` (`AdditionalLayout`) — Level1/2/3/Report layout; stays in Power BI
- Segment1/4/8/10_Map — defined in Qlik but never applied via `ApplyMap()` in `GLStructure` — skipped

---

## Silver Table

### `Dental_Financial_Detail`

**Source values:** `Actual`, `Budget`

**Data sources:**

| Source Value | BRONZE Table | Filter |
|---|---|---|
| `Actual` | `sag.GLPOST` | `FISCALPERD <= '12'` AND (via `AcctType_Map` from `sag.GLAMF`) `AcctType = 'I'` |
| `Budget` | `sag.GLAFS` | `ACTIVITYSW = 1`; unpivoted from `NETPERD1`–`NETPERD12` |
| *(both)* | INNER JOIN `sag.GLAMF` (`GLStructure`) | `Division = 'Dental'` (resolved via `Segment3_Map` / `sag.GLASV` where `IDSEG='000003'`) |

**Key columns:**

| Column | SQL Type | Origin | Notes |
|---|---|---|---|
| `ACCTID` | `VARCHAR(45)` | `GLPOST.ACCTID` / `GLAFS.ACCTID` / `GLAMF.ACCTID` (join key) | Direct passthrough. `RTRIM()` applied at SP layer — source is fixed-length `char`, trailing spaces are a storage artefact, not part of the Qlik business logic |
| `Create_Date` | `DATETIME2` | `GLPOST.AUDTDATE` + `AUDTTIME` | Parsed as `Timestamp#(AUDTDATE&AUDTTIME,'YYYYMMDDhhmmssff')`, converted to Sydney local time. Qlik's `dayname()` wrapper is a display-format-only function — the underlying datetime value is preserved in full, not reduced to a weekday label. Actual rows only (NULL for Budget). **SP implementation note**: naive concatenation of `AUDTDATE`+padded `AUDTTIME` into a single 16-digit string fails `CAST(...AS DATETIME2)` for many rows (confirmed against live data) — SP must build an explicit `YYYY-MM-DD HH:MI:SS.FF` string before casting |
| `Create_User` | `VARCHAR(8)` | `GLPOST.AUDTUSER` | Actual only. `RTRIM()` applied (fixed-length `char` source) |
| `Post_Date` | `DATE` | `GLPOST.JRNLDATE` | `Date(date#(date#(JRNLDATE,'YYYYMMDD'),'YYYYMMDD'))` — date-only, no time component in source. Actual only |
| `Period` | `INT` | Actual: `FISCALYR & FISCALPERD`; Budget: `FSCSYR & PERIOD` (post-unpivot) | YYYYPP numeric format |
| `Journal_ID` | `DECIMAL(18,0)` | `GLPOST.POSTINGSEQ` | Direct passthrough, no precision declared at source. **Verified against live data**: `POSTINGSEQ` (range 9494–27855) and `CNTDETAIL` (range 1–24971) across all 2,748,996 rows have zero decimals — `DECIMAL(18,0)` confirmed correct. Actual only (NULL for Budget) |
| `Journal_Detail` | `VARCHAR(60)` | `GLPOST.JNLDTLDESC` | Actual only. `RTRIM()` applied (fixed-length `char` source; mid-string spaces in free-text descriptions are preserved) |
| `Amount` | `DECIMAL(18,2)` | Actual: `GLPOST.TRANSAMT * -1`; Budget: `GLAFS.NETPERDn * -1` (post-unpivot) | **Verified against live data**: `TRANSAMT` has ~75% of rows with non-zero decimals (2dp); `NETPERDn` columns also carry decimals. `DECIMAL(18,2)` required — source column has no declared precision but actual data is not integer-only |
| `Quantity` | `DECIMAL(18,0)` | `GLPOST.TRANSQTY` | **Verified against live data**: all 2,748,996 rows = `0.000`, field is unused/always zero at source. Actual only |
| `Journal_Ref` | `VARCHAR(60)` | `GLPOST.JNLDTLREF` | Actual only. `RTRIM()` applied (fixed-length `char` source) |
| `Fin_Year` | `INT` | Actual: `GLPOST.FISCALYR`; Budget: `GLAFS.FSCSYR` | |
| `Fin_Period` | `INT` | Actual: `GLPOST.FISCALPERD`; Budget: unpivoted `PERIOD` (`01`–`12`) | |
| `Month` | `TINYINT` | `Month(Date#(ApplyMap('Period_Map',FISCALPERD/PERIOD),'MMM'))` | Calendar month number (1–12). Qlik's `Period_Map` inline table (financial period 01→Jul … 12→Jun) translated to SQL `CASE WHEN` — static 12-row lookup, no source table |
| `Source` | `VARCHAR(10)` | Literal | `'Actual'` or `'Budget'` |
| `Budget_Version` | `VARCHAR(1)` | `GLAFS.FSCSDSG` | Budget only (NULL for Actual). `RTRIM()` applied (fixed-length `char` source) |
| `Account_Display` | `VARCHAR(45)` | `GLAMF.ACCTFMTTD` | `RTRIM()` applied (fixed-length `char` source) |
| `Account_Name` | `VARCHAR(60)` | `GLAMF.ACCTDESC` | `RTRIM()` applied (fixed-length `char` source) |
| `Loc_Code` | `VARCHAR(15)` | `GLAMF.ACSEGVAL05` | `RTRIM()` applied (fixed-length `char` source) |
| `Branch` | `VARCHAR(60)` | `ApplyMap('Segment5_Map', GLAMF.ACSEGVAL05)` → `sag.GLASV.SEGVALDESC WHERE IDSEG='000005'` | Lookup via Segment5_Map, not a direct passthrough. `LEFT JOIN` to `GLASV` (not `INNER JOIN`) — mirrors Qlik `ApplyMap`'s behaviour of returning NULL (not dropping the row) when no mapping match exists. `RTRIM()` applied — **confirmed via live data** that `GLASV.SEGVALDESC` is fixed-length `char(60)` with trailing spaces (e.g. `'Dental'` stored as `'Dental' + 54 spaces`); untrimmed values would break exact-match filtering/joins downstream in Power BI |
| `Account_Num` | `VARCHAR(15)` | `GLAMF.ACSEGVAL01` | `RTRIM()` applied (fixed-length `char` source) |

**Not carried to Silver** (present in Qlik intermediates but dropped before `DentalDetail`):
- `[Account Group]` (`GLStructure`, via `AccountGrp_Map`) — defined but never selected into `DentalDetail`
- `Level1`/`Level2`/`Level3`/`Report` (`AdditionalLayout`) — deliberately excluded; Power BI handles this via direct Excel connection
- `Division`, `ACSEGVAL02`, `ACSEGVAL03`, `ReportKEY` (`GLStructure`) — used only as filter/join keys, not selected into final output
- `[AUDTDATE]` (Budget branch, `TMP2` / source line ~400) — Qlik computes a Sydney-local
  creation timestamp for Budget rows from `GLAFS.AUDTDATE`+`AUDTTIME`, using the same
  `dayname(ConvertToLocalTime(...))` pattern as Actual's `Create_Date`. This computed value is
  never selected into `TMPBUD`'s output column list, so it is dropped before reaching
  `Journals`/`DentalDetail`. This is a genuine gap in the Qlik source (not a data availability
  limitation — the source columns exist and the computation runs, but the result is discarded).
  Per Principle 1, this SP faithfully reproduces the same gap: `Create_Date` is NULL for all
  `Source = 'Budget'` rows in Silver, matching the Qlik QVD's actual output.

**Generated files:**
- `create_table_Dental_Financial_Detail.sql`
- `usp_Load_Dental_Financial_Detail.sql`

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `MedicareRevenue` → `MedicareRevenueforEyeCare.qvd` | Eyewear division reporting — out of scope for Dental project |
| `CostofGoods` → `CostofGoodsforEyeCare.qvd` | Eyewear/general COGS reporting — out of scope for Dental project |
| `AccountGrp_Map` / `sag.GLACCGRP` (`AccPac_GLACCGRP`) | Feeds `GLStructure.[Account Group]`, which is never selected into `DentalDetail` — dead column, no BRONZE table created |
| `AdditionalLayout` (Finance P&L Mapping.xlsx — all 4 Report types: Dental/Eyewear/Health/Consol) | Level1/2/3/Report layout handled entirely in Power BI via direct Excel connection, not translated to SQL |
| Segment1/4/8/10_Map | Defined in Qlik source but never applied via `ApplyMap()` in `GLStructure` — dead mappings |
| `Receipts` (`ReceiptsForFinanceApp.qvd`) | Loaded in source script but never joined/concatenated into `DentalDetail` — unused intermediate |
| Legacy commented-out Daily Budget / custom Calendar logic (~150 lines in source script) | Dead code, superseded by current monthly CrossTable budget approach; confirmed identical between file and latest source except for this commented block |

---

## Files to Generate

```
sql_db/DWH_/15_Dental_Centre_Financial_Dashboard/DentalFinancialDetail_qvd/
├── DESIGN.md                                   ← this file
├── create_table_Dental_Financial_Detail.sql
└── usp_Load_Dental_Financial_Detail.sql
```

---

## Refresh Strategy

`usp_Load_Dental_Financial_Detail` uses `TRUNCATE + INSERT` full refresh pattern.

Must run **before** `usp_Load_Dental_Financial_Actual` (in the parent
`15_Dental_Centre_Financial_Dashboard` project), since the latter's `Actual` source rows are
filtered from this table's `Source = 'Actual'` output.
