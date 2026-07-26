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
- Payroll — Westfund's payroll/HR system (`Payroll.dbo.*` tables)
- AccPac GL — via QVD (`AccPac_GL_Segments.qvd`, `AccPac_GL_Accounts.qvd`) for GL account structure
- Excel — Award rate tables, PayRun Dates lookup (`Manual Data` library)

**Script produces exactly one QVD output**: `DentistLeaveHours.qvd` (single `Store` statement in
the script — verified by scanning for all `Store ... into ... .qvd` statements).

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

### SQL Tables — 9 tables (Payroll database only, Archive excluded, 2 dead/unused tables excluded)

| Table Name | Schema | Database | Role in Script |
|---|---|---|---|
| `_iptblAdditionsDeductions` | dbo | Payroll | `AdditionDeductions_Map` mapping source |
| `_iptblCostAccounts` | dbo | Payroll | `CostCentre_Map` mapping source |
| `_iptblGLBatchDetailsLedgerLink` | dbo | Payroll | `GL_MAP1` mapping source |
| `_eivGLAccounts` | dbo | Payroll | `GL_MAP2` mapping source |
| `_iptblSuperFund` | dbo | Payroll | `SuperFund_Map` mapping source |
| `_ipvLeaveReasons` | dbo | Payroll | `LeaveReason_Map` mapping source |
| `_eivPeriods` | dbo | Payroll | `Period_Map` mapping source |
| `_ipvRBMEmpDetails` | dbo | Payroll | `Employee Details` main table |
| `_ipvEmployeeTrans` | dbo | Payroll | `TransactionsTMP` main table |

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

### QVD Files

| File Name | Library | Used As |
|---|---|---|
| `AccPac_GL_Segments.qvd` | ExtractData | `Segment1_Map`–`Segment10_Map` (script actually uses Segment2/3/4/5/6/7/9 only) |
| `AccPac_GLACCGRP.qvd` | ExtractData | `AccountGrp_Map` mapping |
| `Paragon_security_level.qvd` | ExtractData | `SecurityMap` mapping — **dead code, never applied via `ApplyMap()`** |
| `AccPac_GL_Accounts.qvd` | ExtractData | `Employee Details` AccPac Left Join (Account Group/Company/Division/State/Branch/Product/Cover/Department lookups) |

### Other Files (Excel — no DB equivalent)

| File Name | Library | Used As |
|---|---|---|
| `Award Levels min rates.xlsx` (Sheet5) | Manual Data | `SupportAward` mapping |
| `Award Levels min rates.xlsx` (Sheet5) | Manual Data | `HealthProfessionalAward` mapping |
| `PayRun Dates.xlsx` (Sheet1) | Manual Data | `TransactionsTMP` Pay Week Date lookup |

**Note:** `SupportAward`/`HealthProfessionalAward` feed into `Awards` (the orphan table, excluded
above) — so these two Excel mappings are also effectively out of scope, contingent on the
`Awards` exclusion. `PayRun Dates.xlsx` remains in scope (used by `TransactionsTMP`, which feeds
the final `DentistLeaveHours` output).

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
