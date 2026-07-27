# 18_Arrear_Report — DWH Design

## Project Overview

This folder holds **three independent requests**, grouped together only because they share
the "arrears/payment" subject area. They do not share tables, SPs, or grain — each is designed
and built separately. Do not assume cross-references between them unless explicitly noted.

| # | Request | Qlik Source | Status |
|---|---|---|---|
| 1 | Arrears Report | `arrear_report.md` | Pre-existing, not covered by this design doc |
| 2 | Payment Channel | `Payment_Channel.md` | SILVER built; GOLD views pending |
| 3 | Payment Methods - Advance and Arrears | `Payment_Methods_Advance_and_Arrears.md` | SILVER built; GOLD views pending |

Request 1 (`usp_Load_ArrearsReport.sql` → `dbo.Arrears_Report`) predates this design doc and
is out of scope here — see the file directly. It was confirmed NOT mergeable with either
Request 2 or Request 3: different grain (current-snapshot, one row per active member) and
different data source (`memship` + `security_level`, not `group_key_full_by_branch`).

---

# Request 2: Payment Channel

## Overview

Translates the QlikSense load script `Payment_Channel.md` into a single SQL Server SILVER
fact table (`Payment_Channel`), consumed by two GOLD views (pending) for reporting.

**Source system:** rpsqlrp01 / paragonreporting — Westfund member system (SQL, direct connect,
no QVD sources).

**Architecture decision:** The Qlik script produces two conceptually separate outputs —
`Section3` (monthly receipt/dishonour/member-characteristics history) and `LatestMembership`
(single latest-snapshot per member) — plus a standalone `WalletCard` table sourced from Excel.

After discussion, `Section3` and `LatestMembership` were **merged into one SILVER fact table**
(`Payment_Channel`) at the monthly grain (`Membership_Id` + `Year_Month`), with
`LatestMembership`'s snapshot fields (`Latest_Receipt_Type`, `Direct_Debit_Break_Down`,
`Account_Number`, `Latest_Payment_Frequency`) repeated on every month row for that membership.
This trades some storage redundancy for a single shared ETL pipeline (both outputs pull from
the same `memship`/`receipt`/`receipt_method`/`receipt_method_type` base). Two GOLD views will
split the fact table back into the two original shapes: `vw_Payment_Channel_By_Month`
(monthly detail) and `vw_Payment_Channel_Latest` (one row per member, most recent month).

`WalletCard` (Excel-only, no `membership_id`, cannot join to anything else in this script) is
**deliberately excluded** from SQL entirely — imported directly into Power BI instead.

---

## Architecture

```
BRONZE (read-only)                    SILVER                     GOLD (pending)
────────────────────                  ──────────────────────     ──────────────────────────
memship                    ──┐
receipt                      │
receipt_method                │
receipt_method_type           ├──→    Payment_Channel     ──→    vw_Payment_Channel_By_Month
group_key_full_by_branch      │                             ──→  vw_Payment_Channel_Latest
person_membership             │
person                        │
account                       │
membership_billing_group      │
billing_group                 │
billing_freq                ──┘

WalletCard.xlsx (Manual Data) ──────────────────────────────────→ Power BI (Power Query, direct import)
```

---

## Silver Table

### `Payment_Channel`

**Source Qlik tables replaced:** `Section3` (+ nested `Dishonour`, `Characteristics` loads),
`LatestMembership` (+ nested `DirectDebit`, `LatestPaymentFrequency` loads)

**Data sources:**

| Table | Role | Filter |
|---|---|---|
| `memship` | Active membership filter | `memship_status = 'A'` |
| `receipt` | Receipt transactions | `create_datetime >= '2025-01-01'` (monthly + dishonour only; no date filter on latest-receipt lookup) |
| `receipt_method` | Receipt → method type link | |
| `receipt_method_type` | Method type description | Exclusion list: `NOT IN ('l','O','r','m','c','3','d','n','p','v','1','f','V','u','A','R','j')`; Dishonour uses `= 'A'` |
| `group_key_full_by_branch` | Branch/billing/LOM characteristics | `rundate >= '2025-01-01'` |
| `person_membership` | Primary member link for DOB | `relationship = '1' AND status_flag = 'A'` (in ON clause, not WHERE — preserves LEFT JOIN semantics) |
| `person` | Date of birth | |
| `account` | Direct debit account info | `status_flag = 'A' AND account_type = 'D'` |
| `membership_billing_group` | Latest payment frequency (inlined view logic) | `membership_group_version = MAX(...)` per member |
| `billing_group` | Billing frequency link | |
| `billing_freq` | Billing frequency description | |

**Inlined view:** `paragonreporting.dbo.MemberPaymentFrequencyLatest` was not referenced
directly (SILVER should not cross-depend on a source-system view). Its definition was
inlined as the `LatestPaymentFreq` CTE — same 3-table join + correlated `MAX(membership_group_version)`
subquery.

**Key columns:**

| Column | Origin | Notes |
|---|---|---|
| `Membership_Id` | `memship.membership_id` | |
| `Year_Month` | Derived | `DATEFROMPARTS(YEAR, MONTH, 1)` of `receipt.create_datetime` |
| `Receipt_Method_Type` | `receipt_method.receipt_method_type` | |
| `Receipt_Method_Desc` | `receipt_method_type.description` | |
| `Total_Receipt_Amount` | Derived | `SUM(receipt.receipt_amount)` per member/month/method |
| `Receipt_Count` | Derived | `COUNT(receipt.receipt_id)` |
| `Dishonour` | Derived | Same monthly shape, filtered to `receipt_method_type = 'A'` |
| `Dishonour_Count` | Derived | |
| `Branch_Description` | `group_key_full_by_branch.branch_description` | Joined via `PriorMonth` (see quirk below) |
| `Billing_Freq_Description` | `group_key_full_by_branch.billing_freq_description` | |
| `LOM` | Derived | Completed years since `join_date`, anniversary-adjusted (mirrors Qlik `age(rundate, join_date)`) |
| `LOM_Bracket` | Derived | `CASE` on `LOM`: 0-3 / 3-5 / 5-10 / 10+ yrs |
| `Date_Of_Birth` | `person.date_of_birth` | Via `person_membership` (relationship = primary) |
| `Age_Bracket` | Derived | `CASE` on age computed from `rundate` + `date_of_birth`, anniversary-adjusted (see Fixes below) |
| `Latest_Receipt_Type` | Derived | `receipt_method_type.description` of the single latest receipt per member (`ROW_NUMBER()` on `create_datetime DESC`) |
| `Direct_Debit_Break_Down` | Derived | `'Account'` if `expiry_date IS NULL` or expired, else `'Card'` |
| `Account_Number` | `account.account_number` | |
| `Latest_Payment_Frequency` | `billing_freq.description` | Via inlined `MemberPaymentFrequencyLatest` logic |

**Generated files:**
- `create_table_Payment_Channel.sql`
- `usp_Load_Payment_Channel.sql`

---

## Fixes Applied During Translation (deviations from a literal first-pass translation)

These are places where the initial SQL draft did not faithfully replicate Qlik's `age()`
semantics, found via independent sub-agent review and confirmed by data query before fixing:

1. **Age Bracket used the wrong basis date.** Qlik computes `age(rundate, date_of_birth)`.
   The first SQL draft substituted `YearMonth` (i.e. `PriorMonth`, ~1 month earlier than
   `rundate`). Fixed to use `rundate` (added to the `Characteristics` CTE's output).
2. **Age Bracket was missing the "has birthday occurred yet" adjustment.** Qlik's `age()`
   function returns completed years; the first SQL draft used a bare `DATEDIFF(YEAR, ...)`,
   which over-counts by up to 1 year until the anniversary has passed. Fixed to use the same
   anniversary-adjustment pattern already used for `LOM`:
   `DATEDIFF(YEAR, d1, d2) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, d1, d2), d1) > d2 THEN 1 ELSE 0 END`.
   Quantified impact before fixing: 51,718 of 1,293,590 rows (3.998%) changed bracket.

Both fixes were independently re-verified by a sub-agent review after applying.

---

## Known Quirks Preserved As-Is (faithful to Qlik source, not corrected)

Per Principle 1 (faithfulness to Qlik logic), these are **not** translation errors — they
exist in the original Qlik script and are deliberately replicated rather than silently fixed:

1. **`Characteristics` joins on `PriorMonth`, not `YearMonth`.** Qlik's `Characteristics`
   table keys on `membership_id & PriorMonth` (i.e. `rundate` minus 1 month), while the main
   `Section3` table keys on `membership_id & YearMonth` (the receipt month). This mismatch
   exists in the Qlik source itself (Payment_Channel.md:64 vs :4) and is preserved in the SQL
   join (`rmly.YearMonth = ch.PriorMonth`).
2. **Age Bracket's later CASE branches test `LOM`, not age.** Qlik's nested `if()` for Age
   Bracket (Payment_Channel.md:102-108) re-tests `LOM <= 35/45/55/65` instead of the computed
   age in every branch past the first. Because `LOM` (years of membership) is almost always
   ≤35, this means most members over 25 fall into `'25-35yrs'` regardless of actual age —
   **this looks like a pre-existing defect in the live Qlik report**, not a translation issue.
   Flagged for the business to confirm separately; the SQL replicates the same logic
   character-for-character.

**Data quality checks run against BRONZE (both returned clean — no fix required):**
- `group_key_full_by_branch` was checked for multiple `rundate` values per member per month
  (would cause fan-out/duplicate rows in the fact table via the `PriorMonth` join) — zero
  rows returned, confirmed one `rundate` per member per month.
- `receipt.create_datetime` ties on the "latest receipt per member" lookup were checked —
  8 members have tied timestamps, but in every case the tied receipts share the same
  `receipt_method_type` description, so `ROW_NUMBER()`'s arbitrary tie-break has no effect
  on the `Latest_Receipt_Type` output value.

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `SILVER.dbo.Wallet_Card` (or similar) | Excel-only source (`WalletCard.xlsx`), no `membership_id` to join against any other table in scope — imported directly into Power BI instead |
| Separate `Silver` tables for `Section3` / `LatestMembership` | Merged into one `Payment_Channel` fact table (see Architecture decision above); split back out at the GOLD layer instead |

---

## GOLD Views — Pending Decisions

Two views were discussed but not yet built. Three open questions were raised in conversation
and never resolved before work moved to Request 3 — resolve these before generating the views:

1. **Naming.** Proposed: `vw_Payment_Channel_By_Month` (monthly detail, mirrors `Section3`) and
   `vw_Payment_Channel_Latest` (one row per member, mirrors `LatestMembership`). Not yet
   confirmed with the user.

2. **"Latest" row selection for `vw_Payment_Channel_Latest`.** Proposed approach:
   `ROW_NUMBER() OVER (PARTITION BY Membership_Id ORDER BY Year_Month DESC)`, filtered to
   `rn = 1`. Not yet confirmed — in particular, ties (a member with two rows in the same
   `Year_Month`, e.g. two different `Receipt_Method_Type` values in the same month) need a
   deterministic tiebreaker, similar to the `Latest_Receipt_Type` tie handling already done in
   the SILVER SP itself. Not yet checked whether `Payment_Channel`'s own grain
   (`Membership_Id + Year_Month + Receipt_Method_Type`) can produce more than one row per
   member per month — if so, `vw_Payment_Channel_Latest` needs its own tiebreak logic.

3. **Field scope for `vw_Payment_Channel_By_Month`.** Undecided whether this view should
   project all 18 columns of `Payment_Channel`, or exclude the snapshot-only columns that
   logically belong to `LatestMembership` (`Latest_Receipt_Type`, `Direct_Debit_Break_Down`,
   `Account_Number`, `Latest_Payment_Frequency`) to avoid presenting denormalised/repeated
   values in a monthly-detail view.

---

## Files Generated

```
create_table_Payment_Channel.sql
usp_Load_Payment_Channel.sql
create_view_vw_Payment_Channel_By_Month.sql   (pending)
create_view_vw_Payment_Channel_Latest.sql     (pending)
```

---

## Refresh Strategy

`usp_Load_Payment_Channel` uses `TRUNCATE + INSERT` full refresh, same as all other SILVER
SPs in this repository. It has no dependency on other SILVER tables — can run standalone.

GOLD views (once built) will read directly from `SILVER.dbo.Payment_Channel`, so
`usp_Load_Payment_Channel` must complete before either view is queried for fresh data.

---

# Request 3: Payment Methods - Advance and Arrears

## Overview

Translates the QlikSense load script `Payment_Methods_Advance_and_Arrears.md` into three SQL
Server SILVER tables, consumed by GOLD views (pending) for reporting.

**Source system:** rpsqlrp01 / paragonreporting — Westfund member system (SQL, direct connect,
no QVD sources).

**Important source-file note:** The `.md` file contains **four Qlik script blocks** separated
by `EXIT SCRIPT;` statements — three successive draft iterations of the `Payments`/`Dishonours`/
`CommsDetail`/`Flags`/`Notes`/`MasterCalendar` script, followed by an unrelated `MemberAccount`
script. Qlik scripts execute top-to-bottom and halt unconditionally at `EXIT SCRIPT;` — everything
after the first one is dead code that never runs. **This was confirmed two ways**: (1) Qlik
language semantics (`EXIT SCRIPT` is an unconditional halt), and (2) the user's actual Qlik
Data Model Viewer screenshot for the live app "Payment Methods - Advance and Arrears" shows
exactly 7 tables — `Payments`, `Payments3`, `Dishonours`, `CommsDetail`, `Flags`, `Notes`,
`MasterCalendar` — which matches the first script block exactly (later blocks add fields like
`MonthID`/`Prev_Paying_Type` that do NOT appear in the live model). **Only the first block
(lines 21–279 of the .md, up to the first `EXIT SCRIPT;`) is in scope.** The `MemberAccount`
block and the two later `Payments` draft iterations are out of scope entirely.

**Architecture decision:** The live Qlik script produces 7 tables. `MasterCalendar` (a trivial
`Year`/`Month` derivation from `Payments.RUNDATE`) is **not built in SQL** — it's simple enough
to generate natively in Power BI (DAX `CALENDAR()`/`CALENDARAUTO()` or a Power Query calculated
column), consistent with how `WalletCard` was handled in Request 2.

Of the remaining 6 tables, grain analysis showed:
- `Payments`, `Payments3` (consec_months), `Dishonours` all share the same grain
  (`membership_id` + month) — **merged into one SILVER fact table**, `Member_Payment_Arrears`.
  Note: in Qlik, `Payments3` is actually a table that is **never merged back into `Payments`**
  (no `DROP TABLE`/`RENAME` sequence like `Payments2`→`Payments` or `Payments4`→`Payments` — it
  stays a standalone table, confirmed via the Data Model Viewer screenshot showing it as a
  separate box). The SQL merge is therefore a **deliberate SILVER-layer optimisation beyond
  a literal translation**, explicitly approved by the user. GOLD views (pending) will split
  `Member_Payment_Arrears` back into 3 shapes matching Qlik's `Payments`/`Payments3`/`Dishonours`.
- `CommsDetail` and `Flags` share membership-level (non-monthly) grain, and `Flags` is entirely
  derived from `CommsDetail`'s own columns — **merged into one SILVER table**,
  `Member_Comms_Detail`. This is a natural 1:1 merge (Flags was never really a separate entity).
- `Notes` has a different grain again (one-to-many, multiple notes per membership) and cannot
  be merged into either of the above — kept as its own table, `Member_Notes`.

---

## Architecture

```
BRONZE (read-only)                          SILVER                          GOLD (pending)
──────────────────────────                  ──────────────────────────      ──────────────────────────
group_key_full_by_branch      ──┐
memship                         │
billing_group                   ├──→        Member_Payment_Arrears   ──→    vw_Payments
billing_freq                    │                                     ──→   vw_Payments3 (consec_months)
receipt                         │                                     ──→   vw_Dishonours
receipt_method                  │
receipt_method_type           ──┘

memship                       ──┐
PersonContact                   │
memship_app                     ├──→        Member_Comms_Detail       ──→   vw_CommsDetail
web_security                    │                                     ──→   vw_Flags (or merged into above)
person_membership              ──┘

note                          ──┐
sub_ref_type                    ├──→        Member_Notes              ──→   vw_Notes
sub_sub_ref_type              ──┘

(no BRONZE source — pure calendar)  ─────────────────────────────────────→  Power BI (DAX CALENDAR())
```

---

## Silver Tables

### 1. `Member_Payment_Arrears`

**Source Qlik tables replaced:** `Payments` (built up through `Period`/`Payments2`/`Payments4`/
final `PaymentChange` left-join), `Payments3` (`consec_months`), `Dishonours`

**Data sources:**

| Table | Role | Filter |
|---|---|---|
| `group_key_full_by_branch` | Main monthly membership snapshot | `rundate > '2025-01-01'` |
| `memship` | Status + termination dates | INNER JOIN — members with no `memship` row are dropped |
| `billing_group` | Billing period lookup | LEFT JOIN (Qlik `OUTER JOIN` — see deviation note below) |
| `billing_freq` | Period description lookup | LEFT JOIN, chained off `billing_group` |
| `receipt` | Dishonour receipts | `create_datetime >= '2025-01-01'` |
| `receipt_method` | Receipt → method type link | |
| `receipt_method_type` | Method description | `description = 'Dishonour'` |

**Key columns:**

| Column | Origin | Notes |
|---|---|---|
| `Mbr_Month_Key` | Derived | `membership_id \| ArrearsMonth` (month-start date) |
| `Membership_Id` | `group_key_full_by_branch.membership_id` | |
| `Group_Id` | Derived | `'No Group'` if NULL, else `CAST(group_id AS VARCHAR)` — Qlik mixes string+numeric in one loosely-typed field |
| `Cover_Category` | Derived | `'Athlete'` / `'Ambulance'` / `'All other covers'` via `LIKE` |
| `Advance_Days_Bracket` | Derived | 9-way `CASE` on `member_advance_days` |
| `Arrears_Days_Bracket` | Derived | 7-way `CASE` on `member_arrears_days`, `<=0` → `'Not in Arrears'` |
| `Paying_Type` | Derived | `'Direct Debit'` / `'Direct Payer'` / `'Deceased Members'` / `'Payroll Group'` via `LIKE` on `billing_group_description` |
| `Memship_Status`, `Termination_Date`, `Entry_Termination_Date` | `memship` | Via INNER JOIN |
| `No_Periods`, `Period_Description` | `billing_group.tpt_period`, `billing_freq.description` | |
| `TPT_Date` | Derived | Qlik `Period` residency: only handles Weekly/Fortnightly/Monthly, else falls through to `date_paidto` |
| `Advance_Arrears_Flag` | Derived | `'Advance'` if `TPT_DATE >= RUNDATE` else `'Arrears'` |
| `Arrears_Flag` | Derived | `BIT`, 1 if `TPT_DATE < RUNDATE` |
| `Mbr_Arrears_Key`, `Arrears_Month` | Derived | `membership_id \| MonthStart(RUNDATE)` |
| `Termination_Month_Flag` | Derived | See Fixes below — compares full year+month, not just month name |
| `Sixty_Days_Backdated` | Derived | `'60 days backdated'` if `DATEDIFF(DAY, TerminationDate, EntryTerminationDate) >= 60`, else NULL |
| `Payment_Change` | Derived | `LAG()` window function replicating Qlik `Previous()`, ordered by `membership_id, RUNDATE` |
| `Count_Of_Dishonours`, `Dishonour_Type` | Derived | Monthly count + 3-way bucket (`'Dishonour 1'` / `'Dishonour >1'` / `'No Dishonour'`) |
| `Consec_Months` | Derived | Gaps-and-islands window function pattern replicating Qlik `Previous()`/`Peek()` recursive counter |

**Generated files:**
- `create_table_Member_Payment_Arrears.sql`
- `usp_Load_Member_Payment_Arrears.sql`

---

### 2. `Member_Comms_Detail`

**Source Qlik tables replaced:** `CommsDetail` (two-stage load — base contact info LEFT JOINed,
then `join` (INNER JOIN) to latest `web_security` record), `Flags` (derived columns)

**Data sources:**

| Table | Role | Filter |
|---|---|---|
| `memship` | Base membership | |
| `PersonContact` | Contact details (name, email, mobile) | `relationship = '1'`, LEFT JOIN |
| `memship_app` | `no_contact` flag | LEFT JOIN |
| `web_security` | Postal preference, email, app-registered flag | `main_ref_type = 'P'`, latest `create_datetime` per person, INNER JOIN via `person_membership` |
| `person_membership` | Links `web_security.main_ref_id` (person_id) to `membership_id` | `relationship = '1'` |

**Important behaviour preserved from Qlik:** the second stage is an **INNER JOIN** (Qlik `join`,
not `left join`) — members with no `web_security` record are dropped entirely from the final
table. Verified against real data: this drops the table from 171,157 rows down to 76,165
(55.5% of members have no web_security record and are excluded). This is faithful to the Qlik
source, not a bug — flagging the magnitude for awareness.

**Key columns:**

| Column | Origin | Notes |
|---|---|---|
| `Membership_Id`, `First_Name`, `Surname`, `Detail_Mobile`, `Detail_Email`, `No_Contact` | Base LEFT JOIN chain | |
| `Postal_Preference`, `Email_Address`, `App_Registered` | `web_security` (latest record) | `App_Registered` = `'Yes'`/`'No'` from `CASE WHEN account_active IS NOT NULL` |
| `App_Reg_Flag` | Derived | See Known Quirks below — effectively a constant value in practice |
| `Email_Flag`, `Mobile_Flag` | Derived | See Fixes below — NULL handling corrected |
| `Postal_Pref_Final` | Derived | `'Email'` / `'Post'` cascading CASE |

**Generated files:**
- `create_table_Member_Comms_Detail.sql`
- `usp_Load_Member_Comms_Detail.sql`

---

### 3. `Member_Notes`

**Source Qlik table replaced:** `Notes`

**Data sources:**

| Table | Role | Filter |
|---|---|---|
| `note` | Note text/date | `main_ref_type = 'M'` |
| `sub_ref_type` | Note category | `description IN ('Phone Call','Arrears','Admin-NoContact')`, INNER JOIN |
| `sub_sub_ref_type` | Note sub-category | LEFT JOIN |

**Key columns:**

| Column | Origin |
|---|---|
| `Membership_Id` | `note.main_ref_id` |
| `Note_Text` | `note.note_text` |
| `Note_Create_Date` | `note.create_datetime` |
| `Sub_Ref_Description` | `sub_ref_type.description` |
| `Sub_Sub_Ref_Description` | `sub_sub_ref_type.description` |

**Generated files:**
- `create_table_Member_Notes.sql`
- `usp_Load_Member_Notes.sql`

---

## Fixes Applied During Translation

All three were found and confirmed via real data queries against BRONZE before fixing —
per Principle 1, none were silently corrected without evidence and user approval.

1. **`Termination_Month_Flag` date comparison bug** (`Member_Payment_Arrears`). Qlik's original
   logic (`If(MonthName(TerminationDate) = arrears_month, ...)`) compares a month-NAME string
   against a full date, which — due to Qlik's loose typing — effectively only compares
   month-of-year and ignores the year entirely. Verified against real BRONZE data: **375,308
   rows** would be affected (many members have monthly snapshot history spanning a decade or
   more in `group_key_full_by_branch`, e.g. one sampled member had records from 2015 through
   2026 — so "June" recurs 10+ times for the same member across different years). Fixed to
   compare full year+month: `YEAR(TerminationDate) = YEAR(ArrearsMonth) AND
   MONTH(TerminationDate) = MONTH(ArrearsMonth)`.

2. **`Group_Id` NULL handling** (`Member_Payment_Arrears`). Qlik's
   `If(IsNull(group_id),'No Group', group_id)` mixes a string literal and a numeric column in
   one loosely-typed field — SQL requires explicit `CASE ... CAST(group_id AS VARCHAR(20))`.
   Not a logic bug, just a type-strictness translation requirement.

3. **`Email_Flag`/`Mobile_Flag` NULL handling** (`Member_Comms_Detail`). Qlik's `len(NULL)`
   returns `0`; SQL Server's `LEN(NULL)` returns `NULL`. A literal translation of
   `if(len(detailE)<3, 'No Email', 'Email')` to `CASE WHEN LEN(detailE) < 3 THEN ...` would
   silently mis-classify members with no email address as `'Email'` (since `NULL < 3` is
   `UNKNOWN`, falling through to the `ELSE` branch) instead of `'No Email'`. Verified against
   real data: 48,626 of 171,157 rows (28.4%) have `detailE IS NULL`; 38,046 (22.2%) have
   `detailM IS NULL`. Fixed using `ISNULL(LEN(detailE), 0) < 3` to replicate Qlik's `len(NULL)=0`
   behaviour exactly.

**Two bugs found in `Member_Payment_Arrears` during sub-agent review, before first disk write
(never shipped in a broken state):**

4. **`Arrears_Days_Bracket VARCHAR(13)` too short.** `'Not in Arrears'` is 14 characters —
   would have caused a runtime `String or binary data would be truncated` error, failing the
   entire SP. Fixed to `VARCHAR(20)`.
5. **`Mbr_Month_Key` used the wrong date component.** Draft SQL built the key from `p.RUNDATE`
   (the full day-level date), but Qlik's `MonthStart(date(rundate-1))` uses the month-start
   date. Fixed to build from `p.ArrearsMonth` instead — the JOIN to `Dishonours` was already
   correct (used `ArrearsMonth`), only the emitted key string was wrong.

---

## Known Quirks Preserved As-Is (faithful to Qlik source, not corrected)

1. **`App_Reg_Flag` is effectively a constant value.** Qlik's
   `if(isnull([App Registered]),'No Not App Registered','App Registered')` tests whether the
   *already-converted* `'Yes'`/`'No'` string is NULL — but it never is (verified against real
   data: `account_active` is never NULL in the qualifying rows, so `App_Registered` is always
   `'Yes'`, and this flag always evaluates to `'App Registered'`). This looks like a logic
   redundancy in the Qlik source (the intent was probably to test `account_active IS NULL`
   directly, not the post-conversion string) — replicated character-for-character rather than
   silently "fixed" to test the more sensible condition.
2. **`OUTER JOIN` translated as two `LEFT OUTER JOIN`s, not `FULL OUTER JOIN`.** Qlik's
   `OUTER JOIN` keyword is semantically a full outer join. The SQL uses `LEFT OUTER JOIN` from
   `group_key_full_by_branch` to `billing_group`/`billing_freq` instead, to avoid introducing
   phantom membership-less rows into a fact table that should always be membership-anchored.
   This is a deliberate, disclosed deviation (not silently applied) — whether `billing_group`
   contains `group_id` values absent from `group_key_full_by_branch` for the filtered date
   range was not independently verified against live data; flagged as a residual assumption.

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `SILVER.dbo.Master_Calendar` (or similar) | Trivial `Year`/`Month` derivation from `Payments.RUNDATE` — generated natively in Power BI (DAX `CALENDAR()`) instead, consistent with `WalletCard` handling in Request 2 |
| Anything from `MemberAccount` block, or the 2nd/3rd `Payments` draft iterations | Dead code — appears after the first `EXIT SCRIPT;` in the `.md` file, confirmed never executed by the live Qlik app (see Overview) |

---

## Files Generated

```
create_table_Member_Payment_Arrears.sql
usp_Load_Member_Payment_Arrears.sql
create_table_Member_Comms_Detail.sql
usp_Load_Member_Comms_Detail.sql
create_table_Member_Notes.sql
usp_Load_Member_Notes.sql
create_view_vw_Payments.sql            (pending)
create_view_vw_Payments3.sql           (pending)
create_view_vw_Dishonours.sql          (pending)
create_view_vw_CommsDetail.sql         (pending)
create_view_vw_Notes.sql               (pending)
```

---

## Refresh Strategy

All three SPs use `TRUNCATE + INSERT` full refresh and have no dependency on each other or on
Request 2's `Payment_Channel` — any order is fine:

```
usp_Load_Member_Payment_Arrears
usp_Load_Member_Comms_Detail
usp_Load_Member_Notes
```

`usp_Load_Member_Payment_Arrears` was validated against real BRONZE data with 3 independent
self-consistency checks (Consec_Months state-transition rules, PaymentChange state-transition
rules, Dishonour_Type COUNT() sanity) — all returned 0 violating rows — plus a full execution
test (1,226,261 rows, ~1 minute, no errors).

GOLD views (once built) will read from the 3 SILVER tables above; each SP must complete before
its dependent views are queried for fresh data.
