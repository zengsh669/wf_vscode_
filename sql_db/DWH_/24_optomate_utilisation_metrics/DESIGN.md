# Optomate Utilisation Metrics — DWH Design

## Overview

Explores the **Optomate** SQL Server database (separate from the Paragon/BRONZE-SILVER-GOLD
warehouse) to identify source tables supporting three optometry business metrics.

**Source system:** Optomate (SQL Server, accessed via SSMS). Access level: DML only (read/write
data), no DDL — table/object exploration and querying only, no schema changes.

**Status:** `select_Script_To_Sale_Conversion.sql` is written, tested against live data, and
iterated through 4 commits (see Git history) — draft, not yet business-approved. Chair Utilisation
and Optometrist Utilisation are unblocked for SQL but not yet written.

- **Script-to-Sale Conversion**: Fact table + conversion-rate rollups built. Purchases are matched
  by **patient + date** (not `EXAM_ID` — see reliability finding below) and attributed to exactly
  ONE visit each (the most recent attended visit on/before the purchase date, preferring a
  scripted visit over an unscripted one) — this avoids the double-counting that a naive
  patient+date join produces when a patient has multiple visits. Exclusions use business-confirmed
  rules: `INVOICE.TYPE=6` (returns), `STOCK_TYPE=1` (consultation fee), `CHARGETO='MEDICARE'`, and
  `ITEMCATEGORY.IS_CONSULTATION=1` or `IDENTIFIER IN ('REPR','WOFF','~ACC')` — the last one
  replaced an earlier hand-maintained 41-line product list once a reliable join path was found and
  verified. **Still open**: side-by-side same-day/1-week/2-week window comparison (currently one
  window at a time via `@DateWindowDays`), and a Walk-In Sales summary rollup (detail rows exist,
  no aggregate yet). Not yet reviewed by business.
- **Chair Utilisation**: `APPOINTMENT` duration/status fields and the 12-branch `BRANCH` location
  dimension confirmed. The working-day calendar per branch is directly computable from
  `APPOINTMENT` data — no business input needed. **Blocked on business** only for picking a single
  value from the 12–14 appointments/day range in the "Total Available Chair Hours" formula. SQL
  not yet written.
- **Optometrist Utilisation**: fully ready to build. Numerator (`APPOINTMENT`, attended,
  by `USER_IDENTIFIER`), denominator (`CLOCKINOUT` in/out times), and the optometrist filter
  (`USERS.USER_TYPE=1`, excluding 7 non-person placeholder accounts) are all confirmed against
  real data. SQL not yet written.

---

## Metrics to Build

### 1. Script-to-Sale Conversion (%)

**Definition:** Patients who attended an appointment, obtained a script (prescription), and
subsequently completed a purchase ÷ relevant appointments/patients.

**Data status:** SQL written (`select_Script_To_Sale_Conversion.sql`), tested against live data,
4 commits in. Not yet reviewed or approved by business.

**How the query works (current implementation):**
- **Attendance**: `APPOINTMENT.APP_PROGRESS=5`, excluding `IS_BREAK=1` and `PATIENTID` of `-1`/
  `NULL` (placeholder/break rows not always caught by `IS_BREAK` — confirmed by a colleague,
  2026-09-10).
- **Script**: same-patient/same-day match to `EXAMINATION`, then `EXAMINATION.ID = SPECTACLE_RX.EXAM_ID`.
- **Purchase linking**: patient + date, NOT `EXAM_ID` (see reliability finding below — `EXAM_ID`
  is populated for consultation billing but almost never for retail/dispensing invoices).
- **Purchase attribution — avoids double-counting**: a naive "purchase date ≥ visit date" join lets
  one invoice match every prior visit for that patient (a cross join). Instead, each purchase is
  attributed to exactly ONE visit: the most recent attended visit on or before the purchase date,
  preferring a visit that has a script over one that doesn't (only falling back to the nearest
  visit regardless of script status if the patient has no scripted visit at all). A purchase that
  predates a patient's first visit (or whose patient has no visit) is a **Walk-In Sale candidate**.
- **Exclusions** (all business-confirmed, Kathryn, 2026-09-10): `INVOICE.TYPE=6` (returns);
  `INVOICE_ITEMS.STOCK_TYPE=1` (consultation fee); `CHARGETO='MEDICARE'`; and
  `ITEMCATEGORY.IS_CONSULTATION=1` or `IDENTIFIER IN ('REPR','WOFF','~ACC')` — resolved via
  `INVOICE_ITEMS.STOCK_ID → ITEMS.ID → ITEMS.CATEGORY_IDENTIFIER → ITEMCATEGORY.IDENTIFIER`. This
  join only covers ~52% of `INVOICE_ITEMS` rows, but the uncovered 48% are entirely
  `STOCK_TYPE` 2/3/4/5/8/9 (frames/lenses/contacts/coatings/tints, which should be included
  anyway), while `STOCK_TYPE=7` — the category that actually needs this exclusion logic —
  resolves at 100%. This replaced an earlier hand-maintained 41-line product exclusion list.
- **Grain: per purchase, not per unique patient** (business-confirmed) — a single script commonly
  supports multiple purchases (reading/general-wear/computer glasses bought separately; scripts
  valid 2 years, contacts 12 months; Optomate allows one exam to yield multiple scripts, unlike
  the previous system NetOptic).
- **Output**: a row-level fact table (`#PurchaseDetail`) plus three rollups off `#VisitRollup` —
  overall conversion rate, with-script vs. without-script, and by branch.

**Still open (not yet built):**
- **Side-by-side date-window comparison**: business asked for same-day / 1-week / 2-week windows
  shown together (Qlik's version also checked 6 months as a sanity check — only 1–3% different
  from 2 weeks, so not needed as a primary cut). The query currently reports one window at a time
  via `@DateWindowDays`, changed manually and re-run — no side-by-side output yet.
- **Walk-In Sales summary**: the fact table already flags these rows (`AppointmentID IS NULL`) and
  they can be pulled out with a simple filter, but there's no aggregate (count, total $) built yet.
- **`STOCK_TYPE=7`/`ITEMCATEGORY` sign-off**: business gave the exclusion rule directly
  (`IS_CONSULTATION=1` or `REPR`/`WOFF`/`~ACC`) rather than reviewing our earlier tentative list —
  this is implemented, but the finished query itself hasn't been sent back for a final check.
- **Business review of the finished query/results**: everything above has been confirmed rule-by-
  rule in conversation, but the assembled query and its output have not yet been formally shown
  to Kathryn (or anyone in business) for sign-off.

#### Script-to-Sale reliability finding (2026-09-09, verified against live Optomate data)

Executing the draft query's logic step by step against real data showed:

1. `APPOINTMENT` (attended, `APP_PROGRESS=5`) → `EXAMINATION` via same-patient/same-day match:
   reliable, 96.6% match rate (2,848 / 2,947).
2. `EXAMINATION` → `SPECTACLE_RX` via `EXAM_ID`: reliable. 84% of `SPECTACLE_RX` rows (2,037 /
   2,427) have a valid (non-zero) `EXAM_ID`.
3. `EXAMINATION`/`INVOICE.EXAM_ID` → purchase: **not reliable**.
   - `INVOICE.EXAM_ID` uses `0` to mean "not linked" (not `NULL` — a trap for any query using
     `IS NOT NULL` or `COUNT(EXAM_ID)`, both of which overcount because they don't exclude `0`).
   - Only 2,840 / 8,314 invoices (34%) have a non-zero `EXAM_ID`.
   - Of those 2,840, cross-tabbing against `INVOICE_ITEMS.STOCK_TYPE` showed 2,822 contain only
     consultation-fee-type lines; **only 1 invoice contains an actual retail item**
     (frame/lens/contact lens/coating/tint).
   - Conclusion: `EXAM_ID` is populated reliably for consultation billing, but retail/dispensing
     invoices (the actual "sale" in Script-to-Sale) are almost never linked back to the exam that
     produced them. **Resolved by business**: patient + date matching is the correct, expected
     approach — exact same-date/EXAM_ID linkage was never realistic in practice.

### 2. Chair Utilisation

**Definition:** Total Attended Appointment Duration (hours) ÷ Total Available Chair Hours.

**Total Available Chair Hours derivation:**
Number of working days (excluding days with no appointments, e.g. public holidays)
× 12–14 appointments per day × 5 days per week, **per location** (requires a location split
filter).

**Data status:** numerator (attended appointment duration) and the location dimension (12
branches) are fully confirmed — see Source Table Mapping below. The denominator formula itself is
given in the metric definition and is mostly computable directly from data:
- "Number of working days excluding days with no appointments" — derivable directly from
  `APPOINTMENT` (count distinct dates per branch with at least one attended appointment).
- "5 days per week" — fixed in the definition, not a variable.
- "12–14 appointments per day" — the **only** open parameter; it's a range, not a single value.

**Open items:**
- Need business to pick a single value (or confirm a per-branch value) within the 12–14
  appointments/day range used in the Total Available Chair Hours formula. Everything else in the
  formula can be computed from data already confirmed.

### 3. Optometrist Utilisation

**Definition:** Attended Appointment Duration (hours) ÷ Clinical Hours Worked.

**Data status:** fully ready to build — no open items. Numerator (`APPOINTMENT`, attended, by
`USER_IDENTIFIER`), denominator (`CLOCKINOUT` in/out times), and the optometrist filter
(`USERS.USER_TYPE=1`, excluding 7 non-person placeholder accounts) are all confirmed against real
data. See Source Table Mapping below.

---

## Source Table Mapping (candidates confirmed by column inspection against real data)

| Area | Candidate table(s) | Key columns | Status |
|---|---|---|---|
| Appointments | `APPOINTMENT` | `STARTDATE`, `ENDDATE`, `DURATION`, `BRANCH_IDENTIFIER`, `USER_IDENTIFIER`, `APPOINTMENT_TYPE`, `PATIENTID`, `APP_PROGRESS`, `IS_BREAK` | Column structure confirmed; `APP_PROGRESS` decoded — see row below |
| Appointment types | `APPOINTMENT_TYPES` | `IDENTIFIER`, `DESCRIPTION`, `DEFAULT_DURATION` | Structure confirmed |
| Attendance status | `APPOINTMENT.APP_PROGRESS` (int, no lookup table in dbo schema) | `APP_PROGRESS IN (2,3,4,5,10)` | **Confirmed by business (Kathryn, 2026-09-10)** — full code list obtained from the Optomate front end (no DB-side lookup table exists), see decode table below. Our original data-inferred guess of `APP_PROGRESS = 5` alone was confirmed correct as far as it went, but Kathryn's Qlik logic also includes 2/3/4/10 (Waiting/Pre-test/Consulting/Dilating) as "Attended", to catch patients whose status was never updated to 5=Complete after they arrived. Implemented in `select_Script_To_Sale_Conversion.sql`. |
| Scripts / prescriptions | `SPECTACLE_RX` (glasses), `CONTACT_RX` (contact lenses, 82 rows) | `PATIENTID`, `RXDATE`, `EXAM_ID` | Structure confirmed for `SPECTACLE_RX`; need to confirm whether contact lens scripts count too |
| Exam link (appointment↔script↔sale) | `EXAMINATION` | `ID`, `PATIENT_ID`, `EXAM_DATE`, `COMPLETED`, `FINALISED` | **Verified**: `EXAMINATION.ID` = `SPECTACLE_RX.EXAM_ID` = `INVOICE.EXAM_ID` join confirmed against real data (20-row sample, all `COMPLETED=1` exams). `SPECTACLE_RX` is present for ~13/20 exams (script is optional, not automatic) |
| Sales / purchases | `INVOICE`, `INVOICE_ITEMS` | `INVOICE.PATIENTID`, `SALE_DATE`, `EXAM_ID`, `TYPE`; `INVOICE_ITEMS.DESCRIPTION`, `STOCK_TYPE`, `QTY`, `EXTENDED` | **Important correction from data**: an `INVOICE` is generated for almost every completed `EXAMINATION` (consultation fee), so presence of an `INVOICE` alone does NOT mean a retail purchase happened. "Completed a purchase" must be judged from `INVOICE_ITEMS` line detail (see `STOCK_TYPE` decode below) |

### `APPOINTMENT.APP_PROGRESS` full decode (Kathryn, 2026-09-10 — sourced from the Optomate front
end; no database-side lookup table exists for this column)

| Value | Meaning | Treated as "Attended"? |
|---|---|---|
| 0 | No status set (default option when appointment is made) | No |
| 1 | Confirmed | No |
| 2 | Waiting (has arrived for appt) | **Yes** |
| 3 | Pre-test (has arrived for appt) | **Yes** |
| 4 | Consulting (has arrived for appt) | **Yes** |
| 5 | Complete (has arrived for appt — what every appt should end up as for those who attended) | **Yes** |
| 6 | Cancelled (should then be deleted) | No |
| 7 | No show | No |
| 8 | Appointment cut/paste | No |
| 10 | Dilating (has arrived for appt) | **Yes** |
| 11 | SMS sent (blue phone icon) | No |
| 12 | SMS sent, Y response | No |
| 13 | SMS sent, N response (red phone icon) | No |
| 18 | Calendar reminder sent | No |
| 19 | SMS sent, no Y/N response (yellow phone icon) | No |

**Why 2/3/4/10 are included alongside 5:** Kathryn's Qlik logic treats these as "Attended" because
they all represent a patient who has physically arrived for their appointment — 5=Complete is what
the status *should* end up as by end of day, but staff sometimes forget to update it, so relying
on 5 alone under-counts genuine attendance. Implemented as `APP_PROGRESS IN (2,3,4,5,10)` in
`select_Script_To_Sale_Conversion.sql`. Codes 6/7/8/11/12/13/18/19 remain excluded (cancelled, no
show, or purely SMS/reminder tracking, not attendance).

### `INVOICE.TYPE` decode (from cross-tabbing amount sign and sampled `INVOICE_ITEMS` descriptions, no lookup table found)

| TYPE | Meaning | Count | Evidence | Use in metrics |
|---|---|---|---|---|
| 2 | Standard invoice (majority case — consultation and/or retail mixed) | 7,282 | Overwhelming majority, near-all positive totals | Include; still needs `STOCK_TYPE` line filtering to isolate actual retail purchase |
| 5 | Standard sale invoice, retail-heavy (frames/lenses/contacts) | 963 | All positive totals, avg $577; item samples almost entirely spectacle/sunglass/lens/contact lens product lines | Include as completed sale |
| 1 | Standard sale invoice, small-value (drops/accessories/occasional frame) | 26 | All positive totals, avg $46; item samples are drops, cleaning wipes, occasional frames | Include as completed sale |
| 6 | Return / credit note | 43 | 100% negative totals, avg -$493 | **Exclude** — not a completed purchase |

### Source Table Mapping (continued)

| Area | Candidate table(s) | Key columns | Status |
|---|---|---|---|
| Locations / stores | `BRANCH` | `IDENTIFIER`, `NAME` | Confirmed — 12 branches: BAT (Bathurst), DUB (Dubbo), EME (Emerald), LIT (Lithgow), MAK (Mackay), MAR (Maroochydore), MOR (Moranbah), MUD (Mudgee), ORA (Orange), ROK (Rockhampton), TOW (Townsville), WOL (Wollongong). Most other `BRANCH` columns are third-party integration config, not relevant |
| Optometrist roster / clinical hours | `CLOCKINOUT` | `USER_IDENTIFIER`, `BRANCH_IDENTIFIER`, `IN_TIME`, `OUT_TIME` | Structure confirmed — matches "Clinical Hours Worked" concept |
| Staff / optometrist dimension | `USERS` | `IDENTIFIER`, `FULL_NAME`, `USER_TYPE`, `QUALIFICATION`, `PROVIDERNO` | **Confirmed**: `USER_TYPE = 1` = Optometrist. Verified by cross-tab against `APPOINTMENT`: all 221,600 attended appointments (`APP_PROGRESS=5`) belong to `USER_TYPE=1` users; every other `USER_TYPE` (2,3,4,5) has zero appointments, despite some also having clock-in records (front desk/dispensing/admin staff who clock in but don't see patients). **Important correction**: of the 17 `USER_TYPE=1` records, only 9 are real optometrists with actual clock-in and appointment activity (MB, TB, AL, JMC, RN, ZA, KL, SA, AG, JN — 10 total, one of which (JN) has low volume). The other 7 (`LIT`, `MAK`, `DUB`, `WOL`, `ORA` — branch placeholder accounts; `EXT` — external Rx; `CB` — inactive/admin) have zero clock-in and zero appointments and must be excluded from optometrist headcount/denominator calculations |
| Product/fee category | `INVOICE_ITEMS.STOCK_TYPE` (int, no lookup table found) | 1,2,3,4,5,7,8,9 | **Decoded from sample descriptions** (see table below). Type 7 is a mixed bucket, resolved via `ITEMCATEGORY` (see below), not per-description guessing |
| Exclusion category lookup | `ITEMCATEGORY` (`IDENTIFIER`, `NAME`, `IS_CONSULTATION`) | `IS_CONSULTATION`, `IDENTIFIER` | **Confirmed exclusion rule (Kathryn, 2026-09-10)**: exclude a line if `IS_CONSULTATION=1` or `IDENTIFIER IN ('REPR','WOFF','~ACC')`. Only 4 categories have `IS_CONSULTATION=1` (`~CLC`, `~CON`, `~COT`, `~COS` — all consultation types); `REPR`/`WOFF`/`~ACC` are separate identifiers with `IS_CONSULTATION=0`, added to the rule as an OR, not an AND (business's own SQL phrasing was ambiguous here — clarified in conversation) |
| Category join path | `INVOICE_ITEMS.STOCK_ID → ITEMS.ID → ITEMS.CATEGORY_IDENTIFIER → ITEMCATEGORY.IDENTIFIER` | `STOCK_ID` | **Verified**: resolves ~52% of all `INVOICE_ITEMS` rows, but the unresolved 48% is entirely `STOCK_TYPE` 2/3/4/5/8/9 (frames/lenses/contacts/coatings/tints — included regardless of category), while `STOCK_TYPE=7` — the only category that actually needs this exclusion check — resolves at 100%. Rows with no category match default to "not excluded" |

### `INVOICE_ITEMS.STOCK_TYPE` decode (from sampled descriptions, not an official lookup)

| STOCK_TYPE | Meaning | Count | Use in metrics |
|---|---|---|---|
| 1 | Consultation fee (Initial/Subsequent/Brief Consultation) | 3,158 | **Exclude** — exam fee, not a retail purchase |
| 2 | Spectacle frames (e.g. AVANTI, LACOSTE) | 2,042 | Include as purchase |
| 3 | Sunglasses frames (e.g. RAY-BAN, UGLY FISH) | 1,345 | Include as purchase |
| 4 | Spectacle lenses (e.g. ZEISS, Synchrony) | 3,150 | Include as purchase |
| 5 | Contact lenses (e.g. CooperVision, Alcon, J&J) | 104 | Include as purchase |
| 7 | Mixed: eye health checks, drops/ointments, fitting fees, repairs, freight, write-offs, accessories | 2,334 | Include/exclude resolved via `ITEMCATEGORY` (see above) — no longer needs per-description judgement |
| 8 | Lens coatings (e.g. ZEISS DuraVision AR coating) | 1,044 | Include as purchase (lens add-on) |
| 9 | Lens tints (e.g. ZEISS Tint Gradient/Solid) | 61 | Include as purchase (lens add-on) |

**Historical note:** an earlier pass hand-classified the 41 distinct `STOCK_TYPE=7` product
descriptions as a tentative exclusion list (superseded — see `select_Script_To_Sale_Conversion.sql`
Git history for the commit that replaced it with the `ITEMCATEGORY` rule above).

---

## Open Questions / Next Steps

1. ~~List all schemas/tables in Optomate~~ — done (dbo schema, ~280 tables).
2. ~~Inspect appointment table structure~~ — done. ~~Decode `APPOINTMENT.APP_PROGRESS`~~ — done,
   `APP_PROGRESS = 5` = Attended (inferred via same-day invoice cross-tab, see table above).
3. ~~Verify the `EXAMINATION.ID` = `SPECTACLE_RX.EXAM_ID` = `INVOICE.EXAM_ID` join hypothesis~~ —
   done, confirmed against real data. **New finding:** an invoice exists for almost every
   completed exam (consultation fee), so "completed a purchase" must be determined from
   `INVOICE_ITEMS` line detail, not from invoice existence alone.
4. ~~Identify `INVOICE_ITEMS.STOCK_TYPE` distinct values~~ — done. ~~Resolve `STOCK_TYPE=7`
   include/exclude~~ — done, business gave the rule directly (`ITEMCATEGORY.IS_CONSULTATION=1`
   or `IDENTIFIER IN REPR/WOFF/~ACC`) rather than reviewing the tentative per-description list;
   implemented and verified in `select_Script_To_Sale_Conversion.sql`.
5. ~~Confirm which `INVOICE.TYPE` values represent a genuinely completed sale~~ — done. TYPE 1, 2,
   5 = genuine sales (include); TYPE 6 = return/credit note (exclude) — see decode table above.
6. ~~Confirm which `USERS.USER_TYPE` value(s) identify optometrists~~ — done, `USER_TYPE = 1`
   confirmed via appointment cross-tab (see table above).
7. ~~Confirm location dimension/grain for Chair Utilisation split~~ — done, 12 branches confirmed
   (see table above); use `BRANCH.IDENTIFIER` as the split key.
8. ~~Confirm working-day calendar and 12–14 appointments/day assumption~~ — partially done.
   Working-day calendar is directly computable from `APPOINTMENT` data (distinct dates with an
   attended appointment, per branch) — no business input needed. Remaining: business must pick a
   single value (or per-branch value) from the 12–14 appointments/day range; this is a business
   parameter choice, not something derivable from data.
9. ~~Script-to-Sale purchase linkage via `INVOICE.EXAM_ID` is unreliable~~ — **resolved by
   business (Kathryn, 2026-09-10)**: use patient + date matching instead, confirmed as the
   expected, realistic approach. Implemented with an attribution rule to avoid double-counting
   (see metric section).
10. ~~Grain confirmed as per purchase~~, not per unique patient — implemented.
11. **Still open — build a Walk-In Sales summary rollup** (detail rows already exist in the fact
    table via `AppointmentID IS NULL`, but no count/$-total aggregate yet).
12. **Still open — side-by-side same-day/1-week/2-week window comparison** (currently one window
    at a time via `@DateWindowDays`).
13. **Still open — send the finished Script-to-Sale query/results to business for review.**
    Every rule has been confirmed piecemeal in conversation, but the assembled query and its
    output haven't had a formal check.

## Summary: what's left before SQL can be finalised

| Metric | Data exploration | SQL status | Remaining work |
|---|---|---|---|
| Script-to-Sale Conversion | Complete | **Written and tested** (`select_Script_To_Sale_Conversion.sql`, 4 commits) | Add Walk-In Sales summary rollup; add side-by-side date-window comparison; get business sign-off on the finished query/results |
| Chair Utilisation | Complete | Not started | Business: pick one value from the 12–14 appointments/day range (can use a placeholder, e.g. 13, in the meantime) |
| Optometrist Utilisation | Complete | Not started | None — ready to write with no placeholders needed |
