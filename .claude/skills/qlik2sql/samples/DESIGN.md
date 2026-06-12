# Dental Centre Financial Dashboard — DWH Design

## Overview

Translates the QlikSense load script `Dental_Centre_Financial_Dashboard.md` into a SQL Server
SILVER layer (6 tables) consumed directly by Power BI via Power Query.

**Source systems:**
- D4W (Live) — dental clinic system (SQL, ODBC)
- rpsqlrp01 / paragonreporting — Westfund member system (SQL)
- QVD files — pre-extracted snapshots on prdqs01_atobi
- Excel files — manual budget inputs on prdqs01_atobi

**Architecture decision:** No GOLD view is built. Power BI imports each Silver table
independently via Power Query. Budget Excel files are unpivoted in Power Query and never
pass through SILVER.

---

## Architecture

```
BRONZE (read-only)              SILVER (6 tables)                    Power BI
────────────────────            ──────────────────────────────────   ────────────────────────
D4W Live SQL           ──→      Dental_Financial_Actual      ──→     Power Query
Paragon SQL            ──→      Dental_Payment               ──→     Power Query
QVD files              ──→      Dental_Appointment           ──→     Power Query
                       ──→      Dental_Member_Utilisation    ──→     Power Query
                       ──→      Dental_Dentist_Utilisation   ──→     Power Query
                       ──→      Dental_NPS                   ──→     Power Query

Excel budget files ─────────────────────────────────────────────→   Power Query (Unpivot)
```

---

## Silver Tables

### 1. `Dental_Financial_Actual`

**Source values:** `Actual`, `Non Member Fees`

**Data sources:**

| Source Value | File / Table | Filter |
|---|---|---|
| `Actual` | `TransformData/Finance/DentalFinancialDetail.qvd` | `Source = 'Actual'` AND `Fin Year >= 2024` |
| `Non Member Fees` | `TransformData/Business KPIs Display/DentalNonMember_PotentialFee.qvd` | `Date >= 1/7/2023` |

**Key columns produced by Qlik (to carry into Silver):**

| Column | Origin | Notes |
|---|---|---|
| `Account_Num` | QVD direct | Actual only |
| `ACCTID` | QVD direct | Actual + Budget join key |
| `Create_Date` | QVD direct | Actual only |
| `Create_User` | QVD direct | Actual only |
| `Post_Date` | QVD direct | Actual only |
| `Period` | QVD direct / derived | YYYYPP numeric |
| `Journal_ID` | QVD direct | Actual only |
| `Journal_Detail` | QVD direct | Actual only |
| `Amount` | QVD direct / derived | Actual = journal amount; Non Member = `Non Member Amount - Bill Amount` |
| `Quantity` | QVD direct | Actual only |
| `Journal_Ref` | QVD direct | Actual only |
| `Fin_Year` | QVD direct / derived | Financial year (e.g. 2025) |
| `Fin_Period` | QVD direct / derived | 1–12 within financial year |
| `MonthYear` | Derived | `FORMAT` MMM-YYYY |
| `Month` | QVD direct / derived | Calendar month number |
| `Source` | Literal | `'Actual'` or `'Non Member Fees'` |
| `Budget_Version` | QVD direct | Actual only |
| `Account_Display` | QVD direct | Actual only |
| `Account_Name` | QVD direct | Actual only |
| `Loc_Code` | QVD direct | Actual only |
| `Branch` | QVD direct | Actual only |
| `Level3` | QVD direct | Actual only |
| `Level2` | QVD direct | Actual only |
| `Level1` | QVD direct | Actual only |
| `Report` | QVD direct | Actual only |
| `Allocated_Expense_YN` | Derived | `CASE WHEN Account_Name IN (4 values) THEN 'Yes' ELSE 'No'` |
| `Non_Member_Amount` | QVD direct | Non Member Fees only |
| `Bill_Amount` | QVD direct | Non Member Fees only |
| `PotentialFee` | Derived | `Non_Member_Amount - Bill_Amount` |
| `NonMemberFeeFlag` | Literal | `'Non Member Fees'` (Non Member only) |
| `Non_Member_Fees_Switch` | Derived | `CASE WHEN NonMemberFeeFlag = 'Non Member Fees' THEN 'On' ELSE 'Off'` |
| `Year` | Derived | Calendar year |
| `Date` | Derived | `CAST(MonthYear AS DATE)` (Non Member only) |

**Generated files:**
- `create_table_Dental_Financial_Actual.sql`
- `usp_Load_Dental_Financial_Actual.sql`

---

### 2. `Dental_Payment`

**Source values:** `D4W Payments`

**Data sources:**

| Table | Role |
|---|---|
| `dba.patients_accounts` | Invoice base |
| `dba.account_payment_plan` | Links invoice to payment plan |
| `dba.payment_allocations` | Payment amount applied to invoice |
| `dba.tot_payment` | Payment header (date, type, method) |
| `dba.treat` | Treatment lines (for dentist lookup) |
| `dba.staff` | Dentist name lookup |
| `dba.methods_of_paym` | Payment method description (via MAP) |

**Filter:** `tp.ref_status IS NULL` AND `tp.tot_paym_id IS NOT NULL` AND `Payment_DateTest >= '2023-07-01'`

**Key columns:**

| Column | Origin | Notes |
|---|---|---|
| `Payment_ID` | `dba.tot_payment.tot_paym_id` | |
| `Invoice_ID` | `dba.patients_accounts.id` | |
| `Period` | Derived | `Fin_Period` as Period (YYYYPP numeric) |
| `Amount` | `dba.payment_allocations.amount` | Amount applied to this invoice |
| `Fin_Year` | Derived | From `Payment_DateTest` |
| `Fin_Period` | Derived | 1–12 within financial year |
| `MonthYear` | Derived | `FORMAT(Payment_DateTest, 'MMM yyyy')` |
| `Weekend` | Derived | Week-ending Saturday of payment date |
| `Payment_Method` | Derived | Lookup via `methods_of_paym` |
| `Dentist` | Derived | `UPPER(firstname + ' ' + surname)` from `dba.staff` |
| `Bill_DrNumber` | `dba.staff.pers_code` | |
| `Source` | Literal | `'D4W Payments'` |
| `Payment_Type` | `dba.tot_payment.payment_type` | Numeric |
| `Fin_Year_2` | Derived | FY in `YYYY-YY` string format |

**Generated files:**
- `create_table_Dental_Payment.sql`
- `usp_Load_Dental_Payment.sql`

---

### 3. `Dental_Appointment`

**Source values:** `D4W Appointments`, `Chair Utilisation`, `Chair UtilisationTest`, `Patient Retention`

All four Source values are derived from the same `dba.a_appointments` base query.
They are produced as separate NoConcatenate slices in Qlik, each selecting a different
column subset with additional derived fields.

**Data sources:**

| Table / File | Role |
|---|---|
| `dba.a_appointments` | Appointment base (filter: `ref_status IS NULL`, `pat_id > 0`, `pat_id <> 157373`) |
| `dba.patients_hf` | Health fund membership linkage via `Card_No` |
| `ExtractData/Dental/D4W/D4W_CustomField_MbrNo.qvd` | Member number (`Mbr_No`) and `Member_YorN` flag |
| `TransformData/Business KPIs Display/DentalPatients_Display.qvd` | First appointment date per patient (`First_Appt_Date`) |

**Filter:** `Appt_Date >= '2023-07-01'` AND `Appt_Date <= TODAY()`

**Inline lookup:**

`AgeCohorts` inline table maps age ranges to `AgeCohort` labels:
`0-17`, `18-29`, `30-44`, `45-59`, `60-74`, `75+`

`Appt_Book_To_DrNumber_MAP` inline table maps `app_book_id` to `doct_id`.

**Key columns by Source:**

| Column | D4W Appointments | Chair Utilisation | Chair UtilisationTest | Patient Retention |
|---|---|---|---|---|
| `Raw_ApptKey` | Y | Y | — | Y |
| `Pay_ApptKEY` | Y | — | — | — |
| `Period` | Y | Y | Y | Y |
| `Fin_Year` | Y | Y | Y | Y |
| `Fin_Period` | Y | Y | Y | Y |
| `MonthYear` | Y | Y | Y | Y |
| `Weekend` | Y | Y | Y | Y |
| `Date` | Y | Y | Y | Y |
| `Dentist` | Y | Y | Y | Y |
| `Appt_PatNumber` | Y | Y | — | Y |
| `Appt_Duration` | Y | Y | Y | Y |
| `Appt_Attended_Flag` | Y | Y | — | Y |
| `Appt_FTA_Flag` | Y | Y | — | Y |
| `Appt_UTA_Flag` | Y | Y | — | Y |
| `Appt_WaitingReschedule_Flag` | Y | Y | — | Y |
| `Amount` (Payment Amount) | Y | — | — | — |
| `First_Appt_Date` | Y | — | — | — |
| `New_Patient_Flag_Dental` | Y | — | — | — |
| `Age_at_Appt_TMP` | Y | — | — | — |
| `AgeCohort` | Y | — | — | — |
| `Member_YorN` | Y | — | — | — |
| `ChairID` | — | — | Y | — |
| `DaysTillNextAppt` | — | — | — | Y |
| `ReturnedWithin12Months` | — | — | — | Y |
| `Source` | `D4W Appointments` | `Chair Utilisation` | `Chair UtilisationTest` | `Patient Retention` |

**Note on `Chair UtilisationTest`:** Qlik derives a virtual chair assignment per date using
`IterNo()` (up to 5 chairs). SQL equivalent uses `ROW_NUMBER() OVER (PARTITION BY Date ORDER BY Dentist)`
capped at 5.

**Generated files:**
- `create_table_Dental_Appointment.sql`
- `usp_Load_Dental_Appointment.sql`

---

### 4. `Dental_Member_Utilisation`

**Source values:** `Member Utilisation`

**Data sources:**

| Table / File | Role | Filter |
|---|---|---|
| `paragonreporting.dbo.group_key_full_by_branch` | Monthly membership snapshot | `extras_product_id IS NOT NULL` AND `MONTH(rundate) = 1` AND `rundate > vStartDate_1` |
| `paragonreporting.dbo.group_key_full_by_branch` | Latest snapshot (YTD) | `extras_product_id IS NOT NULL` AND `rundate = MAX(rundate)` |
| `paragonreporting.dbo.person_membership` | Person-level membership details | INNER JOIN on `membership_id` |
| `paragonreporting.dbo.claim_line` | Dental claims for VisitsByYear | `claim_line_status_type = 'P'` AND `service_date > vStartDate_1` |
| `ExtractData/Paragon_ProviderNumber.qvd` | Filter to WF Dental providers | `provider_group_id = 1` |
| `Manual Data/Membership App 2/Care Centre Radius Mapping.xlsx` | 50km postcode filter | `Care Centre = 'Lithgow Care Centre'` AND `Radius = 'Within 50Km'` |

**`vStartDate_1`** = `MakeDate(Year(Today()-3), 7, 1)` — 3 financial years back from today.

**Key columns:**

| Column | Origin | Notes |
|---|---|---|
| `Row_ID` | `group_key_full_by_branch.row_id` | |
| `Mbr_No` | `group_key_full_by_branch.membership_id` | |
| `Cover` | `group_key_full_by_branch.cover` | |
| `Date` | Derived | `CAST(rundate - 1 AS DATE)` (end of month) |
| `EOM_Month` | Derived | Calendar month of EOM date |
| `MonthYear` | Derived | `FORMAT(rundate-1, 'MMM yyyy')` |
| `EOM_Year` | Derived | Calendar year of EOM date |
| `Rundate` | `group_key_full_by_branch.rundate` | |
| `Hosp_Product_ID` | `group_key_full_by_branch.hosp_product_id` | |
| `Extras_Product_ID` | `group_key_full_by_branch.extras_product_id` | |
| `Cover_Type` | Derived | Lookup via `cover_type` table |
| `Memship_Status` | `group_key_full_by_branch.memship_status` | |
| `Count_Active` | `group_key_full_by_branch.count_active` | |
| `Postcode` | `group_key_full_by_branch.postcode` | |
| `Period` | Derived | YYYYPP numeric |
| `Fin_Year` | Derived | From Date |
| `Fin_Period` | Derived | 1–12 |
| `Year` | Derived | Calendar year |
| `EndOfCalYearMonth` | Derived | Calendar month number |
| `Person_ID` | `person_membership.person_id` | |
| `Relationship` | `person_membership.relationship` | |
| `Person_Status` | `person_membership.status_flag` | |
| `Person_Join_Date` | `person_membership.join_date` | |
| `Person_Termination_Date` | `person_membership.termination_date` | |
| `Active_As_At_Time` | Derived | `CASE` on join/termination vs rundate — filtered to `'Active'` only |
| `VisitsByYear` | Derived | `COUNT(DISTINCT VisitKey)` from claim_line, grouped by Mbr_No + Person_ID + Year |
| `Source` | Literal | `'Member Utilisation'` |

**Generated files:**
- `create_table_Dental_Member_Utilisation.sql`
- `usp_Load_Dental_Member_Utilisation.sql`

---

### 5. `Dental_Dentist_Utilisation`

**Source values:** `Dentist Utilisation`

Two distinct ingestion paths with different column sets, combined via UNION ALL.

#### Path A — Admin & Meeting Appointments (from D4W)

| Table | Role |
|---|---|
| `dba.a_appointments` (via `Appointments` intermediate) | Filter: `pat_id IN (158315, 159324)` |

| Column | Value |
|---|---|
| `Raw_ApptKey` | `appoint_id` |
| `Dentist` | `UPPER(ApptBook Dentist Name)` |
| `Appt_PatNumber` | `pat_id` |
| `Date` | `Appt Date` |
| `Weekend` | Week-ending Saturday |
| `Fin_Year` | Derived from Weekend |
| `Fin_Period` | Derived from Weekend |
| `MonthYear` | `FORMAT(Weekend, 'MMM yyyy')` |
| `Period` | Derived YYYYPP |
| `Hrs` | `Appt_Duration / 60` |
| `SourceCalc` | `'AdminMeetingAppts'` |
| `Payroll_KEY` | NULL |
| `Cost_Centre` | NULL |
| `Transaction_Type` | NULL |
| `Leave_Reason` | NULL |
| `Employee_Code` | NULL |
| `Default_Cost_Account_Description` | NULL |
| `Payroll_Run_Date` | NULL |
| `Source` | `'Dentist Utilisation'` |

**Filter:** `Weekend >= '2023-07-01'` AND `Weekend <= TODAY()`

#### Path B — Payroll / Leave Hours (from QVD)

| File | Role |
|---|---|
| `TransformData/Finance/DentistLeaveHours.qvd` | Payroll-sourced dentist hours |

| Column | Value |
|---|---|
| `Raw_ApptKey` | NULL |
| `Dentist` | `UPPER(Full Name)` |
| `Appt_PatNumber` | NULL |
| `Date` | NULL |
| `Weekend` | `FLOOR(Weekend(Payroll Run Date))` |
| `Fin_Year` | Derived from Payroll Run Date |
| `Fin_Period` | Derived from Payroll Run Date |
| `MonthYear` | `FORMAT(Payroll Run Date, 'MMM yyyy')` |
| `Period` | Derived YYYYPP |
| `Hrs` | From QVD |
| `SourceCalc` | From QVD |
| `Payroll_KEY` | From QVD |
| `Cost_Centre` | From QVD |
| `Transaction_Type` | From QVD |
| `Leave_Reason` | From QVD |
| `Employee_Code` | From QVD |
| `Default_Cost_Account_Description` | From QVD |
| `Payroll_Run_Date` | From QVD |
| `Source` | `'Dentist Utilisation'` |

**Filter:** `Weekend >= '2023-07-01'` AND `Weekend <= TODAY()`

**Generated files:**
- `create_table_Dental_Dentist_Utilisation.sql`
- `usp_Load_Dental_Dentist_Utilisation.sql`

---

### 6. `Dental_NPS`

**Source values:** `Dental NPS`

Two ingestion paths combined via UNION ALL.

#### Path A — D4W Treatment Notes (Compliments & Complaints)

| Table | Role | Filter |
|---|---|---|
| `dba.treat` | Treatment base | `description` LIKE `'%Compliment%'` OR `'%Complaint%'` |
| `dba.patients_accounts` | Invoice linkage | LEFT JOIN |
| `dba.procedures` | Item description | LEFT JOIN |
| `dba.gst_tarifs` | GST | LEFT OUTER JOIN |
| `dba.staff` | Provider name | LEFT JOIN |
| `dba.Treat_notes` | Clinical notes | LEFT JOIN on `treat_id` |
| `dba.patients_hf` | Member number | LEFT JOIN on `patient_id` (exclude `157373`) |

| Column | Value |
|---|---|
| `Source` | `'Dental NPS'` |
| `Date` | `Treatment Date Created` (`CAST(treat_date AS DATE)`) |
| `MonthYear` | `FORMAT(treat_date, 'MMM yyyy')` |
| `Month` | Calendar month |
| `Membership_Number` | `hf_member_code` |
| `Comment` | `notes` from `Treat_notes` |
| `NPS_Level` | `CASE WHEN description LIKE '%Compliment%' THEN 'Promoter' WHEN LIKE '%Complaint%' THEN 'Detractor' ELSE 'Passive'` |
| `Year` | Calendar year |
| `Fin_Year` | Derived |
| `Period` | Derived YYYYPP |
| `Fin_Period` | Derived |
| `ResponseId` | NULL |

#### Path B — Qualtrics NPS Survey (PENDING — commented out)

| File | Role | Filter |
|---|---|---|
| `TransformData/NPS_HCS_Data/Qualtrics_NPS_HCS_Data.qvd` | Survey responses | `Interaction = 'Dental'` |

| Column | Value |
|---|---|
| `Source` | `'Dental NPS'` |
| `Date` | `StartDate` |
| `MonthYear` | From QVD |
| `Month` | `MONTH(StartDate)` |
| `Membership_Number` | `MembershipNumber` |
| `Comment` | `Feedback` |
| `NPS_Level` | `NetPromoterLevel` |
| `Year` | Derived |
| `Fin_Year` | Derived |
| `Period` | Derived |
| `Fin_Period` | Derived |
| `ResponseId` | `ResponseId` (Qualtrics-only column; NULL in Path A) |

**Filter:** `Date >= '2023-07-01'` AND `Date <= TODAY()`

> **Note:** Path B SP code is commented out pending `Qualtrics_NPS_HCS_Data.qvd` availability.
> When the QVD becomes available, uncomment the second INSERT block in `usp_Load_Dental_NPS.sql`.

**Generated files:**
- `create_table_Dental_NPS.sql`
- `usp_Load_Dental_NPS.sql`

---

## Power BI Data Connections

### Silver Tables (via SQL Server connector)

| Power Query Query Name | Source | Notes |
|---|---|---|
| `Dental_Financial_Actual` | `SILVER.dbo.Dental_Financial_Actual` | |
| `Dental_Payment` | `SILVER.dbo.Dental_Payment` | |
| `Dental_Appointment` | `SILVER.dbo.Dental_Appointment` | Filter by `Source` as needed per visual |
| `Dental_Member_Utilisation` | `SILVER.dbo.Dental_Member_Utilisation` | |
| `Dental_Dentist_Utilisation` | `SILVER.dbo.Dental_Dentist_Utilisation` | |
| `Dental_NPS` | `SILVER.dbo.Dental_NPS` | |

### Budget Excel Files (via Power Query Unpivot)

All 4 Excel files follow the same Unpivot pattern:

1. Connect to Excel file
2. Select month columns `1` through `12`
3. **Unpivot Selected Columns** → generates `Attribute` (period number) and `Value` (budget amount)
4. Rename: `Attribute` → `Fin_Period`, `Value` → `Amount`
5. Add `MonthYear`, `Period` (YYYYPP), `Fin_Year` derived columns to match Silver table grain

| Power Query Query Name | Source File | Extra Dimension Columns |
|---|---|---|
| `Budget_Financial` | `Manual Data/Dental/Dental Budget FY_2026.xlsx` | `ACCTID`, `Account_Name`, `Level1/2/3`, `Type` |
| `Budget_Appointment` | `Manual Data/Dental/DentalBudget_Appointments.xlsx` | `Dentist` |
| `Budget_DentistUtilisation` | `Manual Data/Dental/DentalBudget_DentistUtilisation.xlsx` | *(none beyond FSCSYR)* |
| `Budget_RevenuePerClinicianHour` | `Manual Data/Dental/DentalBudget_RevenuePerClinicianHour.xlsx` | *(none beyond FSCSYR)* |

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `SILVER.dbo.Dental_Financial_Budget` | 4 Excel budget sources handled entirely in Power Query |
| `GOLD.dbo.vw_Dental_Financial_Dashboard` | Power BI imports 6 Silver tables independently; no UNION ALL view needed |

---

## Files to Generate

```
sql_db/DWH_/15_Dental_Centre_Financial_Dashboard/
├── DESIGN.md                                        ← this file
├── create_table_Dental_Financial_Actual.sql
├── usp_Load_Dental_Financial_Actual.sql
├── create_table_Dental_Payment.sql
├── usp_Load_Dental_Payment.sql
├── create_table_Dental_Appointment.sql
├── usp_Load_Dental_Appointment.sql
├── create_table_Dental_Member_Utilisation.sql
├── usp_Load_Dental_Member_Utilisation.sql
├── create_table_Dental_Dentist_Utilisation.sql
├── usp_Load_Dental_Dentist_Utilisation.sql
├── create_table_Dental_NPS.sql
└── usp_Load_Dental_NPS.sql
```

---

## Refresh Strategy

All Silver SPs use `TRUNCATE + INSERT` full refresh pattern.
Recommended execution order (respects data dependencies):

```
1. usp_Load_Dental_Financial_Actual
2. usp_Load_Dental_Payment
3. usp_Load_Dental_Appointment        ← depends on Appointments intermediate (self-contained within SP)
4. usp_Load_Dental_Member_Utilisation
5. usp_Load_Dental_Dentist_Utilisation
6. usp_Load_Dental_NPS
```

All SPs are independent — order above is for logical clarity only, not a hard dependency.
