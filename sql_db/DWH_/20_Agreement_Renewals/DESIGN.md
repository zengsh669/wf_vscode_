# Agreement Renewals — DWH Design

## Overview

Translates the QlikSense load script `Agreement_Renewals.md` into a single SQL Server
SILVER table consumed directly by reporting / Power BI.

**Source systems:**
- Paragon QVD files — pre-extracted snapshots on prdqs01_atobi (ExtractData library)
- rpsqlrp01 / paragonreporting — Westfund member system (SQL, direct connect)
- Excel file — manual agency exclusion list on prdqs01_atobi (Manual Data library)

**Architecture decision:** No GOLD view is built. The entire Qlik script produces a
single wide table (`Agent`, renamed repeatedly through the load script) — this maps
to one SILVER table: `Agent_Agreement_Renewal`. Two Qlik source objects that are
themselves SQL Server views (`MemberPaymentFrequencyLatest`, and the "latest form"
portion of `MemberCorrespondance`) are inlined as CTEs inside the load SP rather than
built as separate Silver objects — see [Nested View Dependencies](#nested-view-dependencies).
The Excel exclusion list (`agencies_to_exclude_(March_2026).xlsx`) is **not** loaded
into SQL at all; it is applied independently in Power BI.

---

## Architecture

```
BRONZE (read-only)                              SILVER                          Consumer
──────────────────────────────                  ─────────────────────────────   ────────────
BRONZE.dbo.grouping              ──┐
BRONZE.dbo.MemberAgent           ──┤
BRONZE.dbo.memship                ──┤
BRONZE.dbo.PersonContact          ──┤
BRONZE.dbo.MemberCorrespondance  ──┼──→   Agent_Agreement_Renewal   ──→   Power BI
BRONZE.dbo.receipt                ──┤        (usp_Load_Agent_Agreement_Renewal)
BRONZE.dbo.MemberCover            ──┤
BRONZE.dbo.MemberGroup            ──┤
BRONZE.dbo.membership_billing_group ─┤   (inlined as CTE — MemberPaymentFrequencyLatest)
BRONZE.dbo.billing_group          ──┤   (inlined as CTE — MemberPaymentFrequencyLatest)
BRONZE.dbo.billing_freq           ──┘   (inlined as CTE — MemberPaymentFrequencyLatest)

agencies_to_exclude_(March_2026).xlsx ─────────────────────────────────→   Power BI (applied independently)
```

---

## Nested View Dependencies

Two Qlik data sources are themselves SQL Server views rather than raw tables. Per user
decision, both are **inlined as CTEs** inside `usp_Load_Agent_Agreement_Renewal` rather
than built as separate Silver tables/views.

### 1. `MemberPaymentFrequencyLatest`

Original view definition (paragonreporting):

```sql
CREATE OR ALTER VIEW [dbo].[MemberPaymentFrequencyLatest]
AS
SELECT membership_billing_group.membership_id, membership_billing_group.group_id,
       billing_group.payment_freq, billing_group.billing_freq, billing_group.tpt_period,
       billing_freq.description
FROM dbo.membership_billing_group
JOIN dbo.billing_group ON membership_billing_group.group_id = billing_group.group_id
JOIN dbo.billing_freq ON billing_group.billing_freq = billing_freq.billing_freq
WHERE membership_billing_group.membership_group_version =
      (SELECT MAX(membership_group_version) FROM dbo.membership_billing_group AS bg
       WHERE membership_id = membership_billing_group.membership_id)
```

- Source tables confirmed to exist in BRONZE: `membership_billing_group`, `billing_group`, `billing_freq` — all plain tables, no further nested dependencies.
- Qlik script only consumes `description` (aliased `Billing Frequency`), but the CTE will be written faithfully per the view definition.

### 2. `MemberCorrespondance`

Original view definition (paragonreporting), backed by `form_archive` (large table) + `forms`:

```sql
CREATE View [dbo].[MemberCorrespondance]
AS
SELECT main_ref as membership_id, form_archive.sub_ref as person_id, forms.form_id,
       form_archive_id, form_archive.create_datetime, form_archive.status_date,
       web_view_date, isnull(form_archive.letter_subject,forms.description) letter_subject,
       forms.form_category,
       (case when web_view_date is null then 'U' else 'R' end) read_unread
FROM form_archive
JOIN forms ON forms.form_id = form_archive.form_id
AND main_ref_type = 'M' AND main_ref is not null AND main_ref > 0
```

- **Decision:** `form_archive` and `forms` are **not** imported into BRONZE (too large / not worth the cost for this use case). Instead, `BRONZE.dbo.MemberCorrespondance` already exists as an equivalent object with matching columns (`membership_id`, `form_id`, `create_datetime`, etc.) — the load SP references it directly (`SELECT ... FROM BRONZE.dbo.MemberCorrespondance`), no CTE needed for this one.
- **Impact if this source were skipped entirely:** would only affect `Form ID`, `create_datetime`, `Has Form Generated Last 60 Days`, and the downstream `Detrimental Comms Flag` — an isolated compliance flag with no bearing on the rest of the table. Not applicable here since the BRONZE object already exists.

---

## Silver Table

### `Agent_Agreement_Renewal`

**Grain:** One row per Agent ID (`group_id` where `group_type = 'A'`), left-joined out to membership-level detail (`membership_id`) — i.e. one row per Agent/Membership combination introduced by the `MemberAgent` join. **Note:** the `MemberCorrespondance`, `MemberCover`, `MemberGroup`, and `BillingFrequency` (CTE) joins are all keyed on `membership_id` alone; if any of these source tables hold more than one row per `membership_id`, the grain can fan out further than "one row per Agent/Membership". This mirrors Qlik's own `Left Join` behaviour exactly (faithful translation, confirmed via independent sub-agent review — see [Step 9 Review Findings](#step-9-review-findings)) and is not a translation defect.

**Data sources:**

| Source Value | Table | Filter |
|---|---|---|
| Agent base | `BRONZE.dbo.grouping` | `group_type = 'A'` |
| Agent audit fields (2nd pass) | `BRONZE.dbo.grouping` | `(created this month OR updated this month) AND group_type='A' AND description<>'No Agency'` — **NB: AND binds tighter than OR in the original Qlik; translated faithfully, see note below** |
| Member↔Agent link | `BRONZE.dbo.MemberAgent` | — |
| Membership status | `BRONZE.dbo.memship` | — |
| Main member contact | `BRONZE.dbo.PersonContact` | `relationship = 1` |
| Correspondence flag | `BRONZE.dbo.MemberCorrespondance` | `form_id IN ('9114','9115')` |
| Latest receipt | `BRONZE.dbo.receipt` | `receipt_id = MAX(receipt_id)` per membership, `receipt_amount > 0` |
| Product | `BRONZE.dbo.MemberCover` | — |
| Billing frequency | CTE: `membership_billing_group` + `billing_group` + `billing_freq` | latest `membership_group_version` per membership |
| Billing group | `BRONZE.dbo.MemberGroup` | — |

**⚠️ Faithfulness note on operator precedence:** the second `grouping` LOAD's `WHERE` clause reads
`A OR B AND group_type='A' AND description<>'No Agency'` with no grouping parentheses around `A OR B`.
Per Qlik/SQL standard precedence, `AND` binds tighter than `OR`, so this parses as
`A OR (B AND group_type='A' AND description<>'No Agency')` — meaning if condition A (created this
month) is true alone, the row passes regardless of `group_type` or `description`. This was flagged
to the user as a likely unintentional bug, but per Principle 1 (faithfulness) the user confirmed to
translate it exactly as written, preserving Qlik's actual runtime behaviour rather than the
"probably intended" `(A OR B) AND group_type='A' AND description<>'No Agency'` reading. **Note:** the
final SQL does *not* carry an inline comment flagging this (user decision during Step 9 review — see
[Step 9 Review Findings](#step-9-review-findings), finding #4) — this section of DESIGN.md is the
authoritative record of the precedence decision instead.

**Key columns (column / origin / notes):**

| Column | Origin | SQL Type | Notes |
|---|---|---|---|
| `Agent ID` | grouping.group_id | DECIMAL(9,0) | |
| `group_type` | grouping.group_type | CHAR(1) | kept unrenamed, as in Qlik |
| `Agency` | grouping.description | VARCHAR(60) | |
| `Commencement Date` | grouping.commencement_date | DATE | `DATE(FLOOR(...))` |
| `Expiry Date` | grouping.termination_date | DATE | `DATE(FLOOR(...))` |
| `Discount Amount` | grouping.grp_discount_amount / 100 | DECIMAL(19,4) | source is MONEY(19,4); kept at source precision by user decision (no narrowing — avoids silent truncation of bad data) |
| `Agreement Status` | derived (10-branch IF chain vs Expiry Date) | VARCHAR(21) | longest value "Expiring in 6 Months" |
| `NPrint Flag` | derived (Qlik preceding load: `Wildmatch(Agreement Status,'Expiring*','Check*')`) | VARCHAR(6) | value is literal `'NPrint'` or NULL (Qlik `if()` with no else branch) |
| `Agent Name` | grouping.description (2nd pass) | VARCHAR(60) | |
| `Termination Date` | grouping.termination_date (2nd pass), mixed with literal 'Active' | VARCHAR(20) | **user decision:** keep as VARCHAR to match Qlik's mixed date/'Active' output exactly (date formatted D/M/YYYY); NOT narrowed to DATE+NULL, which would silently change the reported semantics |
| `create_operator` | grouping.create_operator | CHAR(16) | |
| `Create Date` | grouping.create_datetime | DATE | |
| `update_operator` | grouping.update_operator | CHAR(16) | |
| `Update Date` | grouping.update_datetime | DATE | |
| `Create Monthyear` | grouping.create_datetime | VARCHAR(9) | `MonthName()` — e.g. "Jan. 2026" |
| `Member Agent Term Date` | MemberAgent.termination_date | DATE | |
| `Member Agent Commencement Date` | MemberAgent.commencement_date | DATE | |
| `membership_id` | MemberAgent.membership_id | DECIMAL(9,0) | join key |
| `memship_status` | memship.memship_status | CHAR(1) | |
| `Current PTD` | memship.date_paidto | DATE | |
| `person_id` | PersonContact.person_id | DECIMAL(9,0) | |
| `Ortto Key` | person_id + '-' + membership_id | VARCHAR(19) | |
| `Main Member Surname` | PersonContact.surname | VARCHAR(40) | |
| `Form ID` | MemberCorrespondance.form_id | DECIMAL(9,0) | |
| `create_datetime` (correspondence) | MemberCorrespondance.create_datetime | DATETIME | unrenamed in Qlik |
| `Has Form Generated Last 60 Days` | derived from create_datetime vs Today()-60 | VARCHAR(3) | 'Yes'/'No' |
| `LatestReceiptAmount` | receipt.receipt_amount | MONEY | |
| `DiscountOnLatestReceipt` | receipt.discount_amount | MONEY | |
| `Discount%OnLatestReceipt` | receipt.discount_percent_used | MONEY | source is MONEY despite % name |
| `Product Description` | MemberCover.Product_Description | NVARCHAR(MAX) | source VARCHAR(8000); upgraded per TEXT-column rule |
| `Billing Frequency` | billing_freq.description (via CTE) | VARCHAR(60) | |
| `Group ID` | MemberGroup.group_id | DECIMAL(9,0) | |
| `Group Description` | MemberGroup.description | VARCHAR(60) | |
| `Billing Group Commencement Date` | MemberGroup.commencement_date | DATE | |
| `membership_group_version` | MemberGroup.membership_group_version | DECIMAL(9,0) | |
| `Expired Agreement Active Member Agent Flag` | derived (Agreement Status = 'Expired' AND Member Agent Term Date IS NULL) | VARCHAR(4) | 'Flag'/'OK' |
| `Detrimental Comms Flag` | derived (Agreement Status = 'Expiring in 45 Days' AND Has Form Generated Last 60 Days = 'Yes') | VARCHAR(4) | 'Flag'/'OK' |
| `Member Added Within 60 Days` | derived (memship_status='A' AND Member Agent Commencement Date within 60 days before Expiry Date) | VARCHAR(4) | 'Flag'/'OK' |

**Generated files:**
- `create_table_Agent_Agreement_Renewal.sql`
- `usp_Load_Agent_Agreement_Renewal.sql`

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `Exclude_Flag` SQL logic (Excel exclusion list) | `agencies_to_exclude_(March_2026).xlsx` is applied independently in Power BI, not loaded into SILVER — user decision |
| Separate Silver table/view for `MemberPaymentFrequencyLatest` | Inlined as CTE inside the load SP — user decision, source tables are plain BRONZE tables with no further dependencies |
| BRONZE import of `form_archive` / `forms` | `BRONZE.dbo.MemberCorrespondance` already exists as an equivalent pre-built object; importing the large underlying detail tables was deemed not worth the cost |
| `GOLD.dbo.vw_Agent_Agreement_Renewal` | Single Silver table is consumed directly; no aggregation/join needed at Gold layer |

---

## Files to Generate

```
sql_db/DWH_/20_Agreement_Renewals/
├── Agreement_Renewals.md                        ← Qlik source (existing)
├── DESIGN.md                                     ← this file
├── create_table_Agent_Agreement_Renewal.sql
└── usp_Load_Agent_Agreement_Renewal.sql
```

---

## Step 9 Review Findings

An independent sub-agent review (Opus model) re-derived every Qlik LOAD block against the final SQL
from scratch. It confirmed the INSERT/SELECT/CREATE TABLE column counts all align (38 columns), CTE
dependency ordering is valid, the `receipt` correlated subquery is faithful, and the operator-precedence
translation (see above) is correct. It raised 5 findings, none blocking (SQL compiles and runs); all were
reviewed with the user and left as-is:

| # | Finding | Decision |
|---|---|---|
| 1 | The `262996`-minute constant (representing 182.64 days) is mis-rounded — precise value is 263002. Two boundary checks ("Current" / "Expiring in 6 Months") are off by ~6 minutes. | Not fixed — impact deemed negligible by user |
| 2 | `AgentStatus` CTE uses `CAST(GETDATE() AS DATETIME)` (includes time-of-day) vs Qlik's `today()` (midnight), and is internally inconsistent with `MemberCorrespondanceCTE` which correctly uses `CAST(GETDATE() AS DATE)`. This can shift Agreement Status boundary results by up to ~1 day depending on what time the SP runs. | Not fixed — user confirmed the SP is scheduled to run daily before business hours (e.g. 5:30am), making the GETDATE() vs today() offset a small, constant, predictable gap rather than a variable one. Acceptable under that operating assumption. |
| 3 | `Termination Date` uses `CONVERT(..., 103)` which produces zero-padded dates (`05/03/2026`) vs Qlik's `D/M/YYYY` format (`5/3/2026`, no leading zeros). | Not fixed — cosmetic only, does not affect correctness (same date, same meaning); column is not consumed by any downstream logic |
| 4 | DESIGN.md (prior version) stated the final SQL would carry an inline comment flagging the operator-precedence behaviour; the comment was never added to the SP. | Not fixed — user decided the comment is unnecessary; DESIGN.md itself serves as the record instead (see note under Faithfulness note on operator precedence, above) |
| 5 | The stated table grain ("one row per Agent/Membership combination") did not account for potential fan-out from `MemberCorrespondance`/`MemberCover`/`MemberGroup`/`BillingFrequency` joins. | Documentation-only issue, not a SQL defect — grain note above has been updated to reflect this |

---

## Refresh Strategy

Single Silver SP using `TRUNCATE + INSERT` full refresh pattern:

```
1. usp_Load_Agent_Agreement_Renewal
```

No dependency ordering required — this is the only Silver object produced by this project.
