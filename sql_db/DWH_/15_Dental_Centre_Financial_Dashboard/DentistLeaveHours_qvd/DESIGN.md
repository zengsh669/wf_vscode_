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

## Parallel Track: Direct ConnX Exploration (alternative to resolving the BLOCKER above)

**Rationale:** rather than wait on Monique's reply about whether `ConnX` corresponds to
`Payroll`, a second approach was tried in parallel: search `ConnX` directly for tables/views
that can supply the 11 needed columns by business meaning, independent of matching `Payroll.md`'s
Qlik logic table-for-table. `ConnX` is confirmed to be an active, in-use HR/payroll system in
its own right (product name "ConnX"), so it plausibly holds the same underlying business data
(leave, hours, cost centres) even if the Qlik script's original `_iptbl*`/`_eiv*`/`_ipv*` table
names don't exist there.

### Confirmed usable sources in ConnX

| Need | ConnX Table/View | Row Count | Notes |
|---|---|---|---|
| Employee ID / Employee Code / Full Name | `dbo.q2employees` | (not re-checked this session; confirmed usable via a reference query from another project) | `emp_code`; `Full Name` = `surname` + `given_name` |
| Leave-side data (`SourceCalc='LeaveHrs'` in Qlik): Hrs, Leave Reason, Transaction Type, Payroll Run Date | `dbo.q2vEmployeeLeaveHistory` | 47,409 | Columns: `emp_code`, `hours`, `reason_desc` (already text), `type_desc`, `date_start`, `date_end`, `date_item_logged` — need to pick which date maps to `Payroll Run Date` |
| Cost Centre dictionary | `dbo.q2cost_accounts` | — | `cost_account_id` → `description`, equivalent to Qlik's `_iptblCostAccounts`/`CostCentre_Map` |
| Worked-hours-side data (`SourceCalc='HrsPaid'` in Qlik): the actual transaction table | `dbo.Q2AIR_Shift_Transaction` | 1,012,949 | Has `emp_id`, `start_local_dt`/`finish_local_dt`, `income_type_id`, `cost_account_code_id` — no direct hours or pay-period field, see open gaps below |
| Transaction Type dictionary (HrsPaid side) | `dbo.Q2AIR_Income_Type` | 30 | `income_type_id` → `name`/`description` |

### Ruled out (table/view exists but is empty — do not reuse these)

`dbo.q2transactions`, `dbo.q2transaction_leave`, `dbo.q2vTimesheetHours`,
`dbo.q2vTimesheetHoursTotal`, `dbo.Q2AIR_Global_Transaction`, `dbo.q2vRptFZ_SalaryTransactions`
— all confirmed 0 rows. These look like superseded/legacy structures; the live system appears
to run on the `Q2AIR_*` prefix (uppercase, underscore) rather than the lowercase `q2*` prefix.

### Considered but rejected as unsuitable

- `dbo.q2vRptEmpTotalHoursPerMonth` (74,015 rows) — only has `Total_hours` aggregated by
  emp_code/year/month; no Transaction Type or Cost Centre breakdown, too coarse.
- `dbo.q2vRptAIRPayrollTransactionsForExport` (19 rows) — field set is an almost perfect match
  (`income_type_name`, `hour_value`, `cost_account`, `period_end_date`, `emp_name`, etc.) but
  row count is far too low to be a stable historical source — looks like a transient "current
  export batch" view built on top of `Q2AIR_Shift_Transaction`, not the underlying full table.

### All 5 gaps resolved — 11/11 columns now have a confirmed ConnX source

1. **`Hrs` for the HrsPaid side — RESOLVED.** `Q2AIR_Shift_Transaction.units` is the hours
   value — verified against a 20-row sample by comparing `units` to the `finish_local_dt` -
   `start_local_dt` time difference; they match exactly (e.g. 18:00→19:00 = 1.0 hour = 1
   unit; 13:30→18:00 = 4.5 hours = 4.5 units). Some rows have `units = 0` despite a non-zero
   time span (also `total_cost = 0`) — likely cancelled/incomplete shifts; may need filtering
   when the SP is built.
2. **`Payroll Run Date` for the HrsPaid side — RESOLVED.** `dbo.q2period_end_dates.pe_date`
   is the equivalent. Confirmed by re-reading the Qlik source: `Period_Map` builds
   `Payroll Run Date` from `Date(Left("Period End",10))` — the source field is literally named
   "Period End", i.e. the period **end** date, not the pay date. `q2period_end_dates` has both
   `pe_date` (period end) and `pay_date` (actual pay date, usually next day) — `pe_date` is the
   correct match. Table is weekly cadence (`pay_frequency = 'Weekly'`), 394 rows. `Q2AIR_Shift_Transaction`
   has no period field itself, so joining requires matching `start_local_dt` into a `pe_date`
   window (period = 6 days before `pe_date` through `pe_date` inclusive, for weekly periods).
   Note: `q2period_end_dates` also has a `co_id` column (company ID) — may need to be included
   in the join if ConnX manages multiple companies/payroll groups; not yet confirmed necessary.
3. **`Cost Centre` JOIN key for the HrsPaid side — RESOLVED.** `Q2AIR_Shift_Transaction.cost_account_code_id`
   joins directly to `q2cost_accounts.cost_account_id` — verified with a 10-row sample, all
   rows matched successfully (sample showed `cost_account_id = 28` → description
   `"Lithgow Dental"` for every row).
4. **`Default Cost Account Description` — RESOLVED, source table changed.** The originally
   suspected table (`dbo.q2employee_cost_accounts`) turned out to be **empty** (0 rows), as
   was a second candidate (`dbo.Q2AIR_Employee_Rule_Set_Group_Cost_Account`, also 0 rows).
   Inferring from `Q2AIR_Shift_Transaction` by "most frequent `cost_account_code_id` per
   employee" was tested and rejected — for a sample employee (`emp_id = 444`), the most common
   value was `NULL` (302 occurrences) ahead of any real cost account (`15`: 211,
   `57`: 19) — too dirty to use as a default. The correct source instead is
   **`dbo.q2vHREmployee_Position.Department`** (the same table already used in the reference
   query from the other project, filtered `WHERE Date_Held_To IS NULL` for the employee's
   current position). This column holds department names, and its distinct values include
   `Lithgow Dentists` — see the note below on the exact string match question.
5. **`Payroll_KEY` — RESOLVED (pure calculated field, no new table needed).** Once #2 was
   resolved, this is simply `Employee ID` + a period identifier concatenated (e.g.
   `emp_code + '|' + CAST(period_end_date_id AS VARCHAR)`), mirroring Qlik's
   `iEmployeeID&'|'&iPeriodID`. No additional data source required.

### Open question: how to identify "dentists" in ConnX — Department vs Role_Name

Re-reading the Qlik source confirms the exact filter used to build `DentistLeaveHours` (line 632):
```
Where [Default Cost Account Description] = 'Employee Dentists';
```
This is an **exact match**, not a wildcard (a separate, unrelated `wildmatch("...", 'Employee
Dentists', 'Lithgow Dental')` exists elsewhere in the script for FTE calculations, but that is
not part of the `DentistLeaveHours` output path and should not be used as a reference here).

**First candidate tried: `q2vHREmployee_Position.Department = 'Lithgow Dentists'`.**
`Department`'s distinct value list does not contain the literal string `'Employee Dentists'`,
but does contain `'Lithgow Dentists'` — plausible as the same role under ConnX's newer
"Location + Role" department naming convention. Cross-check: `COUNT(DISTINCT emp_code) WHERE
Department = 'Lithgow Dentists' AND Date_Held_To IS NULL` = **3 employees**.

**Second, stronger candidate: `q2vHREmployee_Position.Role_Name`.** The same table has a
`Role_Name` column (already used in the reference query from another project) with a direct
job-title granularity. Searching `Role_Name LIKE '%Dentist%'` found 4 distinct values:
`Dentist`, `Dentist Casual`, `Dentist Clinical Lead`, `Associate Clinical Dentist Lead`.
Cross-check: `COUNT(DISTINCT emp_code) WHERE Role_Name IN (...) AND Date_Held_To IS NULL` =
**5 employees** (`Dentist`: 3, `Dentist Clinical Lead`: 1, `Associate Clinical Dentist Lead`: 1,
`Dentist Casual`: 0 currently).

**`Role_Name` is the preferred candidate over `Department`:**
- It's a direct job-title match rather than an inferred department-to-role mapping that relies
  on the "Westfund dental is Lithgow-only" assumption holding true indefinitely
- The 5-person breakdown (3 base + 1 lead + 1 associate lead) reads as a more plausible team
  structure than a flat count of 3
- It doesn't silently misclassify dental-adjacent admin/coordinator roles (`Lithgow Dental
  Administration`, `Lithgow Dental Coordinator Quality/Training` are separate departments,
  correctly excluded either way, but `Role_Name` makes this exclusion explicit rather than
  incidental)

**Working assumption (not yet business-confirmed): filter on
`Role_Name IN ('Dentist', 'Dentist Casual', 'Dentist Clinical Lead', 'Associate Clinical Dentist Lead')`.**
This is better-supported than the `Department` guess but is still not a verified 1:1 mapping to
the old Payroll system's `'Employee Dentists'` value — in particular, whether `Dentist Casual`
should be included is a judgement call, not a certainty. Flagging for Monique to confirm
alongside the existing BLOCKER question, since it can't be fully settled by SQL alone.

### `EmployeeStatus` active/terminated logic — RESOLVED, not needed

`EmployeeStatus` (`Payroll.md` lines 574–598) computes a full Active/Terminated determination
per employee per pay run: it builds `[Termination Date]` (via `TermDate_Map`) and `[Last Payroll
Run]` (whether this is the employee's most recent pay run, via `LastRunDate_Map`), then derives
`[Employee Status]` = `'Terminated'` only when `[Termination Date]-1 <= [Payroll Run Date] AND
[Last Payroll Run]` — i.e. only on an employee's final pay run once their termination date has
passed, not simply "has a termination date".

**But `DentistLeaveHours`'s Left Join into `EmployeeStatus` (line 630–638) only pulls 4 fields:
`Payroll_KEY`, `Employee ID`, `Default Cost Account Description`, `Payroll Run Date`.** The
`[Employee Status]`/`[Active Flag]`/`[Terminated Flag]` fields — the actual output of all this
logic — are never selected. `EmployeeStatus` is used purely as a join vehicle to fetch
`Default Cost Account Description`, which the ConnX rebuild already sources directly from
`q2vHREmployee_Position` (see above) without needing this intermediate table at all.

**Conclusion: this entire Active/Terminated calculation does not need to be replicated.** It's
the same pattern as the AccPac GL fields excluded in "Scope Narrowing" above — Qlik computed it,
but it was never selected into this specific QVD's final output.

**Summary: all 11 columns now have an identified ConnX source, and all three follow-up
questions raised in this exploration are now resolved or explicitly deferred to business
confirmation:**
- (a) **Deferred to Monique**: which `Role_Name`/`Department` value(s) correctly represent
  `'Employee Dentists'` (see above)
- (b) **Still open, not yet checked**: verifying the Transaction Type filter lists (Qlik's
  `wildmatch` lists of Leave/HrsPaid transaction type names) actually match the text values
  found in `q2vEmployeeLeaveHistory.type_desc` / `Q2AIR_Income_Type.name`/`description`
- (c) **Resolved, see immediately above**: `EmployeeStatus`'s Active/Terminated logic is
  confirmed unnecessary — it was never part of `DentistLeaveHours.qvd`'s actual output

**This track does not replace the BLOCKER above** — Monique's confirmation is still useful to
validate the `'Lithgow Dentists'` assumption and cross-check the ConnX findings against the
original Payroll system, so the Jira question remains open regardless of progress made here.

### Split-delivery decision: LeaveHrs branch validated, HrsPaid branch is not

Cross-checking both branches against real employees' own records produced different outcomes:

- **LeaveHrs branch — VALIDATED.** Checked against two employees' actual leave history; both
  matched. See [validation_LeaveHrs.sql](validation_LeaveHrs.sql).
- **HrsPaid branch — NOT YET ACCURATE.** Checked against one employee's actual worked hours;
  the query returned rows the employee confirmed were never worked. See
  [validation_HrsPaid.sql](validation_HrsPaid.sql) for the full list of known issues.

**Decision: share the LeaveHrs branch with Monique now as a partial result, rather than waiting
for HrsPaid to be fixed.** Rationale: LeaveHrs is independently validated and can start business
review (Role_Name dentist filter, Cost Centre NULLs) without being blocked by HrsPaid's issues.
When sharing, must be explicit that this is the leave-records half only, not the complete
`DentistLeaveHours.qvd` (which is LeaveHrs + HrsPaid combined per Qlik's `Concatenate`).

**Root cause investigation for HrsPaid, this session:**
- Confirmed `units = 0` rows in `Q2AIR_Shift_Transaction` are systematic future-shift
  placeholders (rostered but not yet occurred), not deleted/cancelled records — sample rows
  had `is_deleted='N'`, `is_reversal='N'`, `is_current='Y'`, real start/finish timestamps,
  real employee and cost centre. Filter `AND s.units > 0` added to remove these.
- Even with that filter, one employee's records still included ~100 rows of suspiciously
  regular "Normal No Exp" / "BRK30 MIN Unpaid" shifts (exactly 4 per working day, every
  working day in a date range) that the employee confirmed are not real worked hours — this
  looks like a rostering template, not actual paid transactions.
- Working hypothesis (unverified): `Q2AIR_Shift_Transaction` may be ConnX's **rostering**
  table, not the equivalent of Qlik's `_ipvEmployeeTrans` (an actual **payroll transaction**
  table — hours already processed and paid). If true, no amount of additional `WHERE`
  filtering fixes this; a different ConnX table representing processed pay transactions would
  be needed instead. Not yet confirmed with Monique/IT.
- Also confirmed (separately, not blocking): `Cost Centre` is NULL for ~93% of HrsPaid rows
  because `cost_account_code_id` itself is NULL on the source row for that share of records
  (verified 405,897 of 437,346 rows) — not a JOIN failure. Genuine source data gap.

**Also resolved this session — `Default Cost Account Description`/`Cost Centre` NULL reduction
via range-matched position history:** the original `pos.Date_Held_To IS NULL` ("current
position only") join was replaced with a range match —
`p_period.pe_date BETWEEN pos.Date_Held_From AND ISNULL(pos.Date_Held_To, '9999-12-31')` —
so each row gets the position that was actually held **at the time of that payroll run**,
not the employee's present-day position. Verified this matters: `q2vHREmployee_Position` does
hold genuine multi-row position history for many employees (some with up to 6 records). On the
LeaveHrs branch, this reduced NULLs on `Default Cost Account Description`/`Cost Centre` from
4,411 to 545 out of 22,842 rows. Note this is a deliberate departure from Qlik's own logic
(Qlik takes a plain `Distinct` current value from `Employee Details`, no date-range matching) —
justified because it measurably closes a real NULL gap and ConnX's data model supports it,
where Qlik's source table apparently didn't need it.

### LeaveHrs branch submitted to Monique/Aaron/Mario for business review (Jira)

The `validation_LeaveHrs.sql` query (unfiltered — no dentist filter applied, `BRONZE.cnx.*`
table references) was posted to Jira as an internal note to Monique Rust, Aaron Staines, and
Mario Fortunato, asking them to validate the script and its output. Reported as tested against
the author's own leave records and found accurate.

**Two ConnX tables landed into BRONZE this session** (`BRONZE.cnx` schema), via new ADF pipeline
JSON configs added to `sql_db/ADF_parametres/`:
- `tbl_ConnX_q2HRPositional_Chart.json` — `q2HRPositional_Chart` (position/org-chart table;
  `Chart_ID` joins to `q2vHREmployee_Position.Chart_ID`, carries `Job_Classification_ID`)
- `tbl_ConnX_q2esp_job_classification.json` — `q2esp_job_classification` (job classification
  dictionary; `Job_Classification_ID` → `Job_Classification` text, e.g. `DENTIST`,
  `OPTOMETRIST`, `DENTAL ASSISTANT`)

Both confirmed present and populated in `BRONZE.cnx` (checked via `INFORMATION_SCHEMA.COLUMNS`
and row counts) before being used in the query sent to Monique. `q2vEmployeeLeaveHistory`,
`q2employees`, `q2period_end_dates`, `q2vHREmployee_Position` were already landed in
`BRONZE.cnx` prior to this — the query sent to Monique reads entirely from BRONZE, not the
ODS ConnX database directly.

### `Job_Classification` column added (Monique's request, for Eyecare Utilisation)

Monique replied on Jira asking to add the job classification field, to help identify
Optometrists for a separate **Eyecare Utilisation** calc (a different project, reusing this
same ConnX exploration). Added to `validation_LeaveHrs.sql` via a two-step join chain:

```
q2vHREmployee_Position.Chart_ID
  -> q2HRPositional_Chart.Chart_ID       (get Job_Classification_ID)
    -> q2esp_job_classification.Job_Classification_ID   (get Job_Classification text)
```

`q2esp_job_classification` was browsed directly and confirmed to contain both `DENTIST` (ID 16,
plus `SENIOR DENTIST`, `DENTIST CLINICAL LEAD`, `DENTIST CASUAL`, `Associate Clinical Dentist
Lead`/`Associate Clinical Dental Lead`) and `OPTOMETRIST` (ID 11, plus `SENIOR OPTOMETRIST`,
`GRADUATE OPTOMETRIST`, `OPTOMETRIST LEAD`) as distinct values — this is a more granular,
purpose-built classification dictionary than `Role_Name`/`Department`, and **may turn out to be
a better dentist-identification field than the `Role_Name` candidate above** (not yet assessed —
flagging as a new open question).

**Behaviour note (same mechanism as the Cost Centre/Department NULLs above):**
`Job_Classification` is matched via the same `p_period.pe_date BETWEEN
pos.Date_Held_From/Date_Held_To` range join used for Department, so it reflects the
classification of the position **held at the time of that payroll run**, not a fixed
per-employee value. Observed in practice: a single employee can show `NULL` on earlier rows and
a real classification (e.g. `Business Operations Specialist`) on later rows, consistent with a
position/classification change partway through their history. This was called out to Monique
when the updated query was sent, to avoid it being mistaken for a data bug.

**New open question, not yet assessed:** does `Job_Classification` (e.g. `DENTIST` vs
`Role_Name IN ('Dentist', ...)`) produce a cleaner or different dentist headcount than the
`Role_Name` candidate already discussed above? Worth a cross-check once there's a reason to
revisit the dentist filter decision.

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
├── validation_LeaveHrs.sql            ← ad-hoc validation query, LeaveHrs branch (validated)
├── validation_HrsPaid.sql             ← ad-hoc validation query, HrsPaid branch (not yet accurate)
├── create_table_Dentist_Leave_Hours.sql   (name TBD at Step 3)
└── usp_Load_Dentist_Leave_Hours.sql       (name TBD at Step 3)
```

Note: `validation_*.sql` are exploratory ConnX validation queries, not the final BRONZE/SILVER
build artifacts — those (`create_table_*.sql` / `usp_Load_*.sql`) still require Step 1 (BRONZE
mapping) to be unblocked first, per the BLOCKER above.
