# Dentist Leave Hours (Payroll) — DWH Design

## Status: IN PROGRESS — Step 0 confirmed, Step 1 (BRONZE mapping) not yet started

This document tracks progress-to-date on translating the QlikSense load script `Payroll.md`
into a SQL Server SILVER layer table. It will be revised as later `/qlik2sql` steps
(Step 1 onward) are completed.

## Overview

Translates the QlikSense load script `Payroll.md` (Payroll system → `DentistLeaveHours.qvd`)
into a SQL Server SILVER layer table. This script reads Payroll HR/payroll data and produces
`DentistLeaveHours.qvd`, one of the 5 TransformData QVDs consumed by the main
`Dental_Centre_Financial_Dashboard.md` script (feeds `Dental_Dentist_Utilisation`).

**Source system:**
- Payroll — Westfund's payroll/HR system (`Payroll.dbo.*` tables) — **the only source system
  actually required, see "Scope Narrowing" below**
- AccPac GL / Excel — used by the Qlik script's intermediate calculations, but **not required**
  for this Silver table (see "Scope Narrowing")

**Script produces exactly one QVD output**: `DentistLeaveHours.qvd` (single `Store` statement in
the script — verified by scanning for all `Store ... into ... .qvd` statements).

---

## Scope Narrowing: Only Payroll SQL tables are required — no QVD, no Excel

**Finding:** `DentistLeaveHours.qvd`'s own final output (the Qlik `DentistLeaveHours:` table,
script lines 605–644) has only **11 columns**:

```
Payroll_KEY, Employee ID, Cost Centre, Hrs, Transaction Type, Leave Reason,
SourceCalc, Default Cost Account Description, Payroll Run Date, Employee Code, Full Name
```

The main Dashboard (`Dental_Centre_Financial_Dashboard.md`, lines 1078–1096) consumes 10 of
these 11 (all except `Employee ID`).

**None of these 11 columns depend on AccPac GL (QVD) or Excel.** Tracing each column back to
its Qlik source:

| Column | Comes from | Depends on QVD/Excel? |
|---|---|---|
| `Payroll_KEY`, `Cost Centre`, `Hrs`, `Transaction Type`, `Leave Reason`, `Payroll Run Date` | `Transactions` (built from `_ipvEmployeeTrans` + 4 Payroll mapping tables) | No |
| `SourceCalc` | Literal string (`'LeaveHrs'`/`'HrsPaid'`) | No |
| `Employee ID`, `Employee Code`, `Full Name`, `Default Cost Account Description` | `Employee Details` (built from `_ipvRBMEmpDetails`) | No — these 4 fields don't need the AccPac GL Left Join at all |

This means the AccPac GL QVD Left Join into `Employee Details` (Account Group, Company,
Division, State, Branch, Product, Cover, Department — ~10 fields) and most of `Employee
Details`'s other ~40 fields (address, Age, LOS Grp, Termination FinYear, etc.) were never
part of `DentistLeaveHours.qvd`'s output in the first place — Qlik's own `DentistLeaveHours:`
LOAD statement already narrows `Employee Details` down to just `Employee ID`, `Employee Code`,
and `Full Name` before the final Store. Same for `Award Levels min rates.xlsx` (feeds the
orphan `Awards` table, already excluded) and `PayRun Dates.xlsx` (feeds `Transaction Effective
Date`, which isn't one of the 11 columns).

**Practical effect:** the SQL rebuild only needs to replicate the sub-set of `Transactions` and
`Employee Details` logic that produces these 11 columns. It does **not** need:
- Any of the 4 AccPac GL QVD files (`AccPac_GL_Segments.qvd`, `AccPac_GLACCGRP.qvd`,
  `AccPac_GL_Accounts.qvd`, `Paragon_security_level.qvd`)
- Either Excel file (`Award Levels min rates.xlsx`, `PayRun Dates.xlsx`)
- The AccPac-derived fields in `Employee Details` (Account Group/Company/Division/State/
  Branch/Product/Cover/Department) or the ~40 other unused `Employee Details` fields (address,
  Age, LOS Grp, Termination calculations, etc.)

**This is reversible, not a permanent scope cut**: as long as BRONZE lands the full Payroll
source tables (not pre-filtered), any of these omitted fields can be added to the Silver table
later via `ALTER TABLE` + SP update if a future consumer needs them.

**Note on framing vs. `DentalFinancialDetail_qvd`'s exclusions:** this is a different kind of
exclusion from the ones made in the sibling `DentalFinancialDetail_qvd` project. There, excluded
items (`MedicareRevenue`/`CostofGoods`, `AccountGrp_Map`, `Segment1/4/8/10_Map`) were genuine
Qlik dead code or out-of-scope business lines — Qlik itself never used them either. Here, the
AccPac GL fields and most `Employee Details` fields **were** part of Qlik's calculation
pipeline for other tables, but were never selected into `DentistLeaveHours.qvd`'s own final
output — so excluding them isn't "skipping dead Qlik code," it's "not rebuilding intermediate
computations that Qlik itself discarded before this specific QVD's Store statement." The
distinction matters for anyone reviewing this decision later.

---

## Key Decision: Payroll_Archive Excluded (confirmed with Monique Rust, business owner)

The source Qlik script originally reads 5 tables from **both** `Payroll` and `Payroll_Archive`
databases (`_iptblGLBatchDetailsLedgerLink`, `_eivGLAccounts`, `_eivPeriods`,
`_ipvRBMEmpDetails`, `_ipvEmployeeTrans`), merging them via Qlik's implicit Concatenate
(with a `Where Not Exists("Employee ID")` dedup guard on the `Employee Details` Archive branch).

**Confirmed with business (Monique Rust): only pull data from the `Payroll` database. The
`Payroll_Archive` branches are excluded entirely.**

This was verified safe for this specific script: every occurrence of `Payroll_Archive` in
`Payroll.md` has a matching `Payroll` counterpart for the same table (no table exists
*only* in `Payroll_Archive`) — see the 5 pairs above. So "use Payroll only" and "prefer
Active, only fall back to Archive for Archive-only tables" produce an identical result here.

**Structural simplification this enables:**
- `Employee Details` — was 2 LOAD blocks (Actual + Archive, implicit Concatenate, Archive
  branch guarded by `Where Not Exists`) → now a single LOAD block, no UNION ALL needed in SQL
- `TransactionsTMP` — was 2 LOAD blocks (Actual + Archive) → now a single LOAD block, no
  UNION ALL needed in SQL

---

## Step 0: Source Table Discovery (confirmed)

### QVD Files and Excel Files — NONE required

Per the "Scope Narrowing" finding above, none of the 11 output columns depend on any QVD file
or Excel file. All 4 QVD files (`AccPac_GL_Segments.qvd`, `AccPac_GLACCGRP.qvd`,
`AccPac_GL_Accounts.qvd`, `Paragon_security_level.qvd`) and both Excel files (`Award Levels
min rates.xlsx`, `PayRun Dates.xlsx`) are out of scope for this rebuild.

### SQL Tables — Payroll database only, Archive excluded, dead/unused tables excluded

Base list of 9 tables (Archive branches + `_iptblTerminationReason`/`_iptblEmployee` already
excluded — see reasons below). **Still open**: whether `_iptblGLBatchDetailsLedgerLink`,
`_eivGLAccounts`, and `_iptblSuperFund` are needed — see note below the table.

| Table Name | Schema | Database | Role in Script | Needed for the 11 output columns? |
|---|---|---|---|---|
| `_iptblAdditionsDeductions` | dbo | Payroll | `AdditionDeductions_Map` mapping source | Yes — feeds `Transaction Type` |
| `_iptblCostAccounts` | dbo | Payroll | `CostCentre_Map` mapping source | Yes — feeds `Cost Centre` |
| `_iptblGLBatchDetailsLedgerLink` | dbo | Payroll | `GL_MAP1` mapping source | **No** — only feeds `Employee Details.ACCTID`, which is not one of the 11 columns |
| `_eivGLAccounts` | dbo | Payroll | `GL_MAP2` mapping source | **No** — same reason as `GL_MAP1` |
| `_iptblSuperFund` | dbo | Payroll | `SuperFund_Map` mapping source | **No** — only feeds `Super Fund Name`, which is not one of the 11 columns |
| `_ipvLeaveReasons` | dbo | Payroll | `LeaveReason_Map` mapping source | Yes — feeds `Leave Reason` |
| `_eivPeriods` | dbo | Payroll | `Period_Map` mapping source | Yes — feeds `Payroll Run Date` |
| `_ipvRBMEmpDetails` | dbo | Payroll | `Employee Details` main table | Yes — feeds `Employee ID`/`Employee Code`/`Full Name`/`Default Cost Account Description` (only these 4 of Employee Details' ~50 fields are needed) |
| `_ipvEmployeeTrans` | dbo | Payroll | `TransactionsTMP` main table | Yes — feeds `Payroll_KEY`/`Cost Centre`/`Hrs`/`Transaction Type`/`Leave Reason`/`Payroll Run Date` |

**Open decision (not yet confirmed by user):** `_iptblGLBatchDetailsLedgerLink`, `_eivGLAccounts`,
and `_iptblSuperFund` can all be dropped from scope since none of their output fields
(`ACCTID`, `Super Fund Name`) are among the 11 columns needed. If confirmed, the final table
list narrows from 9 to **6 tables**:
`_iptblAdditionsDeductions`, `_iptblCostAccounts`, `_ipvLeaveReasons`, `_eivPeriods`,
`_ipvRBMEmpDetails`, `_ipvEmployeeTrans`.

**Excluded from scope (confirmed):**

| Table | Reason |
|---|---|
| `_iptblGLBatchDetailsLedgerLink` (Payroll_Archive) | Archive branch excluded per Monique confirmation |
| `_eivGLAccounts` (Payroll_Archive) | Archive branch excluded per Monique confirmation |
| `_eivPeriods` (Payroll_Archive) | Archive branch excluded per Monique confirmation |
| `_ipvRBMEmpDetails` (Payroll_Archive) | Archive branch excluded per Monique confirmation |
| `_ipvEmployeeTrans` (Payroll_Archive) | Archive branch excluded per Monique confirmation |
| `_iptblTerminationReason` (`Termination_Map`) | Dead code — mapping table defined but never called via `ApplyMap()` anywhere in the script |
| `_iptblEmployee` (`Awards` table) | Orphan table — computes `Award Minimum Hourly Rate` etc. but the `Awards` table itself is never joined into `Employee Details` or any downstream table; the surrounding `LIB CONNECT TO` pair is a Qlik connection-switching mechanism with no SQL equivalent needed |
| `AccPac_GL_Segments.qvd`, `AccPac_GLACCGRP.qvd`, `AccPac_GL_Accounts.qvd`, `Paragon_security_level.qvd` (all QVD) | None of the 11 output columns depend on AccPac GL data — see "Scope Narrowing" above |
| `Award Levels min rates.xlsx`, `PayRun Dates.xlsx` (both Excel) | Feed fields (`Award Minimum Hourly Rate`, `Transaction Effective Date`) that are not among the 11 output columns — see "Scope Narrowing" above |

---

## BLOCKER: Where does `Payroll` actually live? (Step 1 cannot proceed until resolved)

**Open question raised while starting Step 1 (BRONZE object mapping).** Before mapping the
9 confirmed SQL tables to BRONZE, we need to know which physical SQL Server database `Payroll`
(and `Payroll_Archive`) actually is. Investigation so far:

**`Payroll.md` has no `LIB CONNECT TO` statement for Payroll.** The only two `LIB CONNECT TO`
lines in the file are:
```
LIB CONNECT TO 'PRDSQL03 (prdqs01_atobi)';                                  -- line 390, before the (excluded) Awards table
LIB CONNECT TO 'PRDSQL03-MERIDIAN - Connx LIVE (westfund_russellm)';        -- line 419, after Awards/FTE
```
Neither connects to something named "Payroll". Yet every `SQL SELECT ... FROM Payroll.dbo."..."`
in the file (starting from line 1) executes without a preceding connect statement in this file.

**Why this still runs:** `Payroll.md` is only **one tab** of a larger QlikSense App — it is not
a complete, standalone script. QlikSense concatenates all tabs of an App in tab order and
executes them as one continuous script sharing connection state. A `LIB CONNECT TO` executed in
an earlier tab (e.g. a "Connections" tab that isn't part of this repo file) stays active for all
subsequent tabs until the next `LIB CONNECT TO` switches it. So `Payroll.md` is relying on a
connection established in a tab we have not seen. (This is the same pattern as
`DentalFinancialDetail_qvd/Finance_Dashboard.md` and the main
`Dental_Centre_Financial_Dashboard.md`, except those two files happen to contain their own
`LIB CONNECT TO` lines — this one does not.)

**Candidate lead, not yet confirmed:** the line 419 connection string contains the literal text
`"Connx LIVE"` — suggesting the `ConnX` database (which does exist in the ODS, confirmed via
SSMS at `prdsql05.westfund.com.au\ODS`) might be related to server `PRDSQL03-MERIDIAN`. However:
- A precise `INFORMATION_SCHEMA.TABLES` search for all 9 confirmed table names in `ConnX`
  returned **zero matches**.
- A fuzzy `LIKE` search on `ConnX` only surfaced unrelated tables under completely different
  naming conventions (`q2ESP_*` — looks like an Employee Self-Service module, and `q2vRpt*` —
  looks like timecard/report views), not the `_iptbl*` / `_eiv*` / `_ipv*` naming style used by
  the 9 Payroll tables.
- **Working assessment: ConnX is likely NOT the Payroll database** — the naming conventions are
  too different, and this script's `Payroll` connection was never proven to include ConnX. But
  this is not certain without business/IT confirmation, since ConnX could theoretically host
  Payroll data under a divergent naming scheme from a past migration.

**Question sent to Monique Rust (via Jira, awaiting reply):**
1. Is ConnX the correct database corresponding to Payroll?
2. Do we (this project) have access to query ConnX in the ODS?
3. If both confirmed — help map the 9 confirmed table names to their ConnX equivalents (or
   confirm no mapping exists and Payroll is a separate, not-yet-identified database).

**Blocks:** Step 1 (BRONZE object mapping) cannot start until this is resolved — we don't yet
know which physical database/server the 9 source tables should be pulled from into BRONZE.

---

## Not Yet Decided (pending later steps)

- **Which physical database is `Payroll`** (see BLOCKER above) — must be resolved before Step 1
- BRONZE-layer object mapping for the 9 confirmed SQL tables (Step 1) — these will very likely
  require **new ADF pipelines**, since Payroll is a data source not yet landed in BRONZE (unlike
  AccPac GL, which already had partial ADF coverage before this project)
- Silver table naming and file organisation strategy (Step 3)
- Column data types (Step 4)
- Final architecture diagram, key columns table, refresh strategy — to be added once Steps 1–4
  are complete

---

## Files to Generate (provisional — confirmed once Step 3 is done)

```
sql_db/DWH_/15_Dental_Centre_Financial_Dashboard/DentistLeaveHours_qvd/
├── DESIGN.md                          ← this file
├── Payroll.md                         ← Qlik source script (already committed)
├── create_table_Dentist_Leave_Hours.sql   (name TBD at Step 3)
└── usp_Load_Dentist_Leave_Hours.sql       (name TBD at Step 3)
```
