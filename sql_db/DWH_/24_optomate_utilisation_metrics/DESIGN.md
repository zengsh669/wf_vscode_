# Optomate Utilisation Metrics — DWH Design

## Overview

Explores the **Optomate** SQL Server database (separate from the Paragon/BRONZE-SILVER-GOLD
warehouse) to identify source tables supporting three optometry business metrics.

**Source system:** Optomate (SQL Server, accessed via SSMS). Access level: DML only (read/write
data), no DDL — table/object exploration and querying only, no schema changes.

**Status:** `select_Script_To_Sale_Conversion.sql` is written, tested against live data, and
iterated through 6 commits (see Git history) — draft, not yet business-approved.
`select_Chair_Utilisation.sql` is written and tested against live data — logic runs cleanly, but
results are not usable yet because the denominator relies on unconfirmed placeholder parameters
(see below). `select_Optometrist_Utilisation.sql` is written and tested against live data — logic
runs cleanly and a join-fan-out bug in the METRICS stage has been found and fixed, but the output
is **not yet trustworthy**: the numerator counts every attended appointment at a branch regardless
of which optometrist saw the patient, while the denominator only counts hours for the 10 optometrists
matched in ConnX — locum optometrists' appointments inflate the numerator with no offsetting
denominator hours, biasing utilisation upward by an unknown amount (see below).

- **Script-to-Sale Conversion**: Fact table + conversion-rate rollups built. `HasScript` checks
  both `SPECTACLE_RX` and `CONTACT_RX` (Kathryn, 2026-09-11). Purchases are matched by **patient +
  date** (not `EXAM_ID` — see reliability finding below) and attributed to exactly ONE visit each
  (the most recent attended visit on/before the purchase date, preferring a scripted visit over an
  unscripted one) — this avoids the double-counting that a naive patient+date join produces when a
  patient has multiple visits. Exclusions use business-confirmed rules: `STOCK_TYPE=1`
  (consultation fee), `CHARGETO='MEDICARE'`, and `ITEMCATEGORY.IS_CONSULTATION=1` or
  `IDENTIFIER IN ('REPR','WOFF','~ACC','~MIS')` — `INVOICE.TYPE=6` (returns) is now **included**,
  not excluded (business-confirmed, 2026-09-14). The `ITEMCATEGORY` rule replaced an earlier hand-maintained 41-line
  product list once a reliable join path was found and verified. A bug where `Converted` was
  wrongly forced to 0 for every unscripted visit was found and fixed 2026-09-11 (overall conversion
  rate moved 48.9% → 53.1%) — see the metric section for details. **Still open**: side-by-side
  same-day/1-week/2-week window comparison (currently one window at a time via `@DateWindowDays`),
  a Walk-In Sales summary rollup (detail rows exist, no aggregate yet), and whether the purchase-
  attribution rule's bias toward "With Script" should change now that the `Converted` bug is fixed.
  Not yet reviewed by business.
- **Chair Utilisation**: `select_Chair_Utilisation.sql` written and tested (2026-09-10) — fact
  table (`#ChairAppointmentDetail`, one row per attended appointment) + a per-branch metrics
  rollup, same two-stage structure as Script-to-Sale. Only 5 branches (DUB/LIT/MAK/ORA/WOL) have
  appointment activity. Test run produced Chair Utilisation of 44%–94% across branches, but **these
  numbers are not usable** — they're entirely driven by the unconfirmed `SlotsPerDay`/
  `MinutesPerSlot` placeholders (13, 30), not business-approved values. The numerator and
  Working-Days calculation are solid; only the denominator parameters are open.
- **Optometrist Utilisation**: `select_Optometrist_Utilisation.sql` written and tested (2026-09-11)
  — grain is **branch + day, not per-optometrist** (a deliberate scope decision, see below).
  Numerator reuses the same "attended" fact table pattern as Chair Utilisation. Denominator
  (`Clinical Hours Worked`) abandoned `CLOCKINOUT` (Optomate) after finding a single clock-in
  writes one row per branch the employee has access to — confirmed to affect real optometrists,
  not just non-optometrist accounts — and pivoted to ConnX (a separate HR/payroll database):
  10-person hand-maintained roster (Work Pattern hours minus leave, matched to Optomate via
  optometrist name — no shared key) → `select_Clinical_Hours_Worked.sql` (standalone denominator
  draft) → re-embedded in the full metric file. A join-fan-out bug in the METRICS stage (joining
  the un-rolled-up fact table directly to a one-row-per-branch/day denominator, inflating one
  branch's denominator to 9,590 hours instead of a few hundred) was found and fixed 2026-09-11.
  Test run produced utilisation of 33%–59% across branches, but **an independent review (2026-09-11)
  found this is not yet trustworthy**: the numerator counts every attended appointment regardless of
  which optometrist saw the patient, but the denominator only has hours for the 10 ConnX-roster
  optometrists — locum optometrists (Kathryn separately mentioned ~5 of them) contribute fully to
  the numerator with zero denominator offset, which can only inflate utilisation, direction and
  magnitude unknown. The Cost Centre→`BRANCH_IDENTIFIER` mapping is also still unverified against
  real ConnX data (see below).

---

## Metrics to Build

### 1. Script-to-Sale Conversion (%)

**Definition:** Patients who attended an appointment, obtained a script (prescription), and
subsequently completed a purchase ÷ relevant appointments/patients.

**Data status:** SQL written (`select_Script_To_Sale_Conversion.sql`), tested against live data,
6 commits in. Not yet reviewed or approved by business.

**How the query works (current implementation):**
- **Attendance**: `APPOINTMENT.APP_PROGRESS IN (2,3,4,5,10)` (Waiting/Pre-test/Consulting/Complete/
  Dilating — full code list confirmed by Kathryn from the Optomate front end, 2026-09-10; see
  decode table below), excluding `IS_BREAK=1` and `PATIENTID` of `-1`/`NULL` (placeholder/break
  rows not always caught by `IS_BREAK` — confirmed by a colleague, 2026-09-10).
- **Script**: same-patient/same-day match to `EXAMINATION`, then `EXAMINATION.ID = SPECTACLE_RX.EXAM_ID`
  OR `EXAMINATION.ID = CONTACT_RX.EXAM_ID` — a spectacle prescription or a contact lens
  prescription both count as "has a script" (Kathryn confirmed contact lens scripts count too,
  2026-09-11).
- **Purchase linking**: patient + date, NOT `EXAM_ID` (see reliability finding below — `EXAM_ID`
  is populated for consultation billing but almost never for retail/dispensing invoices).
- **Purchase attribution — avoids double-counting**: a naive "purchase date ≥ visit date" join lets
  one invoice match every prior visit for that patient (a cross join). Instead, each purchase is
  attributed to exactly ONE visit: the most recent attended visit on or before the purchase date,
  preferring a visit that has a script over one that doesn't (only falling back to the nearest
  visit regardless of script status if the patient has no scripted visit at all). A purchase that
  predates a patient's first visit (or whose patient has no visit) is a **Walk-In Sale candidate**.
- **Exclusions** (business-confirmed, Kathryn, 2026-09-10; updated 2026-09-14):
  `INVOICE_ITEMS.STOCK_TYPE=1` (consultation fee); `CHARGETO='MEDICARE'`; and
  `ITEMCATEGORY.IS_CONSULTATION=1` or `IDENTIFIER IN ('REPR','WOFF','~ACC','~MIS')` — resolved via
  `INVOICE_ITEMS.STOCK_ID → ITEMS.ID → ITEMS.CATEGORY_IDENTIFIER → ITEMCATEGORY.IDENTIFIER`. This
  join only covers ~52% of `INVOICE_ITEMS` rows, but the uncovered 48% are entirely
  `STOCK_TYPE` 2/3/4/5/8/9 (frames/lenses/contacts/coatings/tints, which should be included
  anyway), while `STOCK_TYPE=7` — the category that actually needs this exclusion logic —
  resolves at 100%. This replaced an earlier hand-maintained 41-line product exclusion list.
  **Updated 2026-09-14 (business-confirmed):** `INVOICE.TYPE=6` (returns) is now included rather
  than excluded, and `~MIS` was added to the `ITEMCATEGORY` exclusion list alongside
  `REPR`/`WOFF`/`~ACC`.
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
  (`IS_CONSULTATION=1` or `REPR`/`WOFF`/`~ACC`/`~MIS`) rather than reviewing our earlier tentative
  list — this is implemented, but the finished query itself hasn't been sent back for a final check.
- **Business review of the finished query/results**: everything above has been confirmed rule-by-
  rule in conversation, but the assembled query and its output have not yet been formally shown
  to Kathryn (or anyone in business) for sign-off.
- **`HasScript` now includes `CONTACT_RX` (fixed 2026-09-11)** — previously only checked
  `SPECTACLE_RX`; a patient who only received a contact lens script was wrongly treated as
  `HasScript=0`. Kathryn confirmed (2026-09-11) contact lens scripts should count the same as
  spectacle scripts. Fix: `ScriptFlag` now also `LEFT JOIN CONTACT_RX cr ON cr.EXAM_ID =
  efa.ExamID`, condition is `sr.ID IS NOT NULL OR cr.ID IS NOT NULL` (83 `CONTACT_RX` rows, all
  `TRIAL_ONLY=0`, joins via `EXAM_ID` the same way as `SPECTACLE_RX` — no trial-only rows to filter
  out). This can widen the known fact-table duplication below, since two RX tables now both join
  on `ExamID`. (Also checked `EXAM_EXTRA_RX`, another RX-suffixed table — currently empty, 0 rows,
  excluded from consideration.)
- **Bug found and fixed 2026-09-11 — `Converted` was wrongly conditioned on `HasScript`.** The
  original formula was `HasScript = 1 AND <has a purchase>`, which forced `Converted = 0` for every
  `HasScript = 0` visit regardless of whether a purchase actually happened — making the "No Script"
  row in the with/without-script comparison always show a 0% conversion rate by definition, not by
  data (confirmed in a live run: several `HasScript = 0` appointments had real linked invoices, yet
  `Converted` was 0 for all of them). Root cause: `HasScript` is a grouping dimension for the
  with/without-script comparison, but it had also been baked into the fact itself. Fix: `Converted`
  is now just `<has a purchase>`, with `HasScript` left as a separate column to group/filter by
  downstream. After the fix (same live data): overall conversion rate 48.9% → 53.1%; No Script
  conversion rate 0% → 12.5% (With Script stayed at 73.9%). All three rollup queries needed no
  changes — the fix was entirely in the `#PurchaseDetail` fact table's `Converted` column.
- **New open question raised by the above fix — the purchase-attribution rule still favours
  "With Script" once script ever existed for that patient.** The `OUTER APPLY` in
  `AttributedPurchases` ranks a scripted visit ahead of a closer unscripted one (see "Purchase
  attribution" above). Now that `Converted` no longer depends on `HasScript`, this ranking's only
  remaining effect is which group (With Script / No Script) a purchase's conversion gets counted
  under, and how `DaysAfterAppointment` comes out for the `@DateWindowDays` check. Practical
  consequence: a "No Script" conversion can currently only occur for a patient with **no scripted
  visit at all** in their history — if a patient has ever had a scripted visit, every later purchase
  attributes to that visit (or the most recent scripted one) over any closer unscripted visit, even
  if the purchase happened right after an unscripted visit. So the With Script vs No Script
  comparison currently measures "has this patient ever had a script" more than "did this specific
  visit have a script" — worth flagging if this comparison is shown to business, and worth deciding
  whether the attribution rule should change now that its original motivation (maximising
  `Converted` under the old, buggy formula) no longer applies.
- **Known duplication in the fact table's join chain (verified 2026-09-11):**
  - 13 `(PATIENT_ID, EXAM_DATE)` pairs have more than one `EXAMINATION` row (one has 3) — i.e. the
    join from `AttendedAppointments` to `EXAMINATION` (by patient + date) is not always 1:1.
  - 45+ `EXAM_ID` values have more than one `SPECTACLE_RX` row (mostly 2, one has 3, one has 4) —
    confirmed NOT a left/right-eye split (`RIGHT_EYE`/`LEFT_EYE` both 0 on sampled duplicates);
    looks like a re-entered/corrected prescription (same patient/exam/`RXDATE`, `DATE_ADDED` a few
    minutes apart) rather than two genuinely different scripts.
  - **Effect on `#PurchaseDetail` row count**: either kind of duplication can make a single
    `AppointmentID` appear on more than one row in the raw fact table. This does NOT affect
    `Conversion_Rate` or the other rollup numbers, because `#VisitRollup` groups by `AppointmentID`
    and uses `MAX(HasScript)`/`MAX(Converted)` — safe against duplicate rows for a 0/1 flag. It WOULD
    affect any calculation done directly on `#PurchaseDetail` without first rolling up by
    `AppointmentID` (e.g. a raw `COUNT(*)` or `SUM(LineAmount)` on the fact table would double-count
    these rows). Anyone querying `#PurchaseDetail` directly should be aware of this.
  - **Effect on `HasScript` specifically — checked and confirmed correct behaviour (2026-09-11)**:
    an independent review raised the concern that if the `EXAMINATION` duplication causes one
    `AppointmentID` to carry both a scripted and an unscripted exam row, `MAX(HasScript)` would
    always resolve to 1 (scripted) even when only one of the two exams actually had a script —
    potentially overstating `Visits_With_Script`. Verified against live data: **9 AppointmentIDs**
    have exactly this pattern (2 rows each, one `HasScript=0` and one `HasScript=1`). Business
    confirmed (2026-09-11): when one appointment resolves to two exam rows and only one has a
    script, it should still count as "has a script" — so `MAX(HasScript)` is the **correct**
    behaviour here, not a bug. (Affects 9 / 2,959 attended visits, ~0.3% — immaterial to the
    conversion-rate figures either way, but now confirmed correct rather than just "probably
    small.")
  - **A separate fan-out risk was also checked and ruled out (2026-09-11)**: the same independent
    review flagged that the `ITEMS`/`ITEMCATEGORY` lookup joins used both for the exclusion rule
    and for the display columns `ItemCategoryIdentifier`/`ItemCategoryName` could fan out
    `QualifyingPurchaseLines` if `ITEMS.ID` or `ITEMCATEGORY.IDENTIFIER`
    were not unique, inflating purchase-line counts and `LineAmount` sums before attribution ever
    happens. Verified against live data: both `ITEMS.ID` and `ITEMCATEGORY.IDENTIFIER` are unique
    (zero duplicate groups for either). This fan-out risk does not exist in the current data — no
    change needed.
- **`@ScriptFilter` is only safe at its default value `'ALL'` — do not switch it without revisiting
  this note first (found 2026-09-11, not fixed, by design — see below).** `AttributedPurchases`'s
  `OUTER APPLY` sources candidate visits from `VisitBase`, which is already filtered by
  `@ScriptFilter`. Under the default `'ALL'`, this is a no-op (nothing is filtered out) and every
  number in this document was produced with `'ALL'`. But if `@ScriptFilter` is ever set to
  `'WITH_SCRIPT'` or `'NO_SCRIPT'`, the pool of visits available for attribution shrinks along with
  it — e.g. under `'NO_SCRIPT'`, no scripted visit exists in `VisitBase` at all, so the "prefer a
  scripted visit" priority in the attribution rule becomes meaningless and purchases that should
  attribute to a scripted visit instead fall back to an older unscripted one or become an
  unattributed Walk-In Sale candidate — silently changing `Converted`/`DaysAfterAppointment` in a
  way neither the SQL header comment nor (until now) this document mentioned. Decision: not fixing
  this now, since the variable is only ever run at `'ALL'` in practice. If `WITH_SCRIPT`/
  `NO_SCRIPT` are ever actually needed, attribute from the unfiltered visit set first, then apply
  `@ScriptFilter` only to what's displayed.

#### Script-to-Sale reliability finding (2026-09-09, verified against live Optomate data)

Executing the draft query's logic step by step against real data showed (this pass predates the
later `APP_PROGRESS IN (2,3,4,5,10)` expansion — figures below use the original `=5` inference):

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

**Total Available Chair Hours derivation, per branch:**

```
Working Days × SlotsPerDay × MinutesPerSlot / 60
```

- **Working Days** — computed from data, not assumed: `COUNT(DISTINCT CAST(STARTDATE AS DATE))` in
  `APPOINTMENT`, per branch. This already excludes days with zero appointments (e.g. public
  holidays), matching the definition's wording exactly. The original definition's "× 5 days per
  week" is **not** applied as a separate multiplier — it was the assumption behind how "working
  days" would come out, not an independent factor; multiplying by it again would double-count the
  week-length dimension that's already implicit in the working-day count.
- **SlotsPerDay** and **MinutesPerSlot** — both open business parameters (the 12–14/day range
  doesn't specify a single number, and there's no standard-slot-length field anywhere in the
  schema). Both are placeholders, one row per branch, in a `@SlotConfig` table variable — not
  global constants — because there's no reason to assume every branch runs the same appointment
  density or the same slot length:

  ```sql
  DECLARE @SlotConfig TABLE (BranchIdentifier VARCHAR(10), SlotsPerDay INT, MinutesPerSlot INT);
  INSERT INTO @SlotConfig VALUES
      ('DUB', 13, 30),
      ('LIT', 13, 30),
      ('MAK', 13, 30),
      ('ORA', 13, 30),
      ('WOL', 13, 30);
  ```

  (13 = midpoint of the 12–14 range, 30 min = placeholder slot length — both to be replaced
  per-branch once business confirms.)

**Data status:** numerator (attended appointment duration) and the location dimension are fully
confirmed — see Source Table Mapping below. Working Days is fully data-derivable; SlotsPerDay and
MinutesPerSlot remain open business parameters, placeholder for now.

**Numerator verified (2026-09-10):** `APPOINTMENT.DURATION` (minutes) matches
`DATEDIFF(MINUTE, STARTDATE, ENDDATE)` exactly for every attended row — 0 mismatches across all
appointments with `APP_PROGRESS IN (2,3,4,5,10)` and `IS_BREAK=0`. `DURATION` can be summed
directly (÷60 for hours) without recomputing from the two datetime columns.

**Branches confirmed active in `APPOINTMENT` data (2026-09-10):** only 5 of the 12 `BRANCH` rows
have appointment activity — DUB, LIT, MAK, ORA, WOL (date ranges span 2026-02-23 through
2027-12-31, i.e. `APPOINTMENT` includes future/already-scheduled rows, not just historical ones —
relevant if a fixed reporting date range is added later; the numerator is unaffected since
"attended" statuses can't exist for future dates).

**SQL status:** `select_Chair_Utilisation.sql` written and tested (2026-09-10), 2,933 attended-
appointment rows in the fact table, all 5 active branches present with plausible per-appointment
durations (30/45/60 min). Structure mirrors Script-to-Sale: `#ChairAppointmentDetail` (fact table,
one row per attended appointment — numerator fields only) → `@SlotConfig` (denominator
placeholders) → a per-branch metrics rollup query. Test-run results (all using the 13/30
placeholders — **not usable as real figures**):

| Branch | Working Days | Attended Hours | Available Hours (placeholder) | Chair Utilisation |
|---|---|---|---|---|
| DUB | 82 | 499.4 | 533.0 | 93.7% |
| LIT | 130 | 678.0 | 845.0 | 80.2% |
| MAK | 114 | 635.0 | 741.0 | 85.7% |
| ORA | 80 | 377.5 | 520.0 | 72.6% |
| WOL | 22 | 63.25 | 143.0 | 44.2% |

**Open items:**
- Business to confirm/replace `SlotsPerDay` and `MinutesPerSlot` per branch in `@SlotConfig` — this
  is the only remaining blocker; once real values are in, the query needs no other changes.
- WOL has only 22 working days in the data so far — much thinner sample than the other 4 branches;
  its utilisation figure will be noisier and less comparable until more data accumulates.
- Numerator and denominator should share the same date-range filter once one is added (mirrors
  `@DateWindowDays` in the Script-to-Sale query) — not yet built. Not currently a correctness issue
  (attended statuses can't exist on the future-dated rows in `APPOINTMENT`), just a gap if a fixed
  reporting period is wanted later.

### 3. Optometrist Utilisation

**Definition:** Attended Appointment Duration (hours) ÷ Clinical Hours Worked.

**Grain: branch + day, not per-optometrist (deliberate scope decision, 2026-09-11).** The ConnX
roster only covers optometrists with clean HR records (the ~5-6 permanent staff); locum
optometrists are not yet distinguished or included (see "known gap" below), so a per-person split
isn't reliable yet — a branch/day total sidesteps needing to attribute each appointment to a named
optometrist.

**Numerator**: `select_Optometrist_Utilisation.sql`'s `#OptometristAppointmentDetail` — identical
fact-table pattern to `select_Chair_Utilisation.sql` (same "attended" filter:
`APP_PROGRESS IN (2,3,4,5,10)`, `IS_BREAK=0`, `PATIENTID>0`), rolled up to branch+day in the
METRICS stage. Carries `OptometristIdentifier` (`USER_IDENTIFIER`) as a column, but that column is
currently unused downstream — see "known gap" below.

**Denominator — `CLOCKINOUT` (Optomate) ruled out (2026-09-11): systemic data-quality issues.**
Originally assumed usable as-is (see prior status below), but exploration found:
- `IN_TIME`/`OUT_TIME` are `TIME`-only columns (no date) — the date must come from `TIMESTMP`
  (verified: `CAST(TIMESTMP AS DATE)` matches `CAST(DATE_ADDED AS DATE)` for 100% of rows, so
  `TIMESTMP`'s date part is a reliable "which day is this record for" key).
- Same-optometrist-same-day multiple records are common, not rare: of all same-day gaps between
  consecutive clock-ins, 401 were under 15 minutes (likely duplicate/system-generated), 132 were
  15–60 minutes, and only 310 were over 60 minutes (a plausible real gap between shifts).
- Root cause (sampled): a single clock-in action appears to write one row **per branch the
  employee has access to**, not one row for the branch they're actually working at that moment —
  e.g. optometrist AE clocked in at LIT (07:49) and MAK (07:55) within the same 15 minutes, with
  overlapping/implausible IN/OUT pairs (one case: IN 17:10, OUT 17:11 — a 1-minute "shift").
  Confirmed this affects **real, confirmed optometrists** too (not just non-optometrist accounts):
  SA and MB both show multi-branch same-day clock records — ruling out "just filter out the bad
  accounts" as a fix, since the issue is systemic, not user-specific.
  - No independent roster/timesheet/shift table exists in Optomate to cross-check against —
    `CLOCKINOUT` is the only table matching `%CLOCK%`/`%ROSTER%`/`%SHIFT%`/`%TIMESHEET%`/
    `%SCHEDULE%`/`%ATTENDANCE%` in `INFORMATION_SCHEMA.TABLES`.
- **Decision: abandon `CLOCKINOUT` for this metric's denominator.**

**Denominator — ConnX approach, built (2026-09-11): `select_Clinical_Hours_Worked.sql`
(standalone draft) and re-embedded in `select_Optometrist_Utilisation.sql`.** Not Optomate — a
separate database, joined to Optomate data via optometrist name matching, not a shared key.
Two layers:

1. **Layer 1 — theoretical hours, no leave.** A hand-maintained `@OptometristRoster` table variable
   (name, `BranchIdentifier`, `PositionFrom`/`PositionTo`, `HoursPerDay`, `DaysOff`) — see roster
   table below — joined against **working days** (branch/days with an actual attended appointment
   in Optomate, same definition as Chair Utilisation's Working Days — NOT a calendar spine, since
   that would wrongly count public holidays as expected-work days). For each branch/day, count how
   many rostered optometrists are on duty (in their employment window, not on a day off) ×
   `HoursPerDay`.
2. **Layer 2 — subtract leave.** ConnX's `q2vEmployeeLeaveHistory.hours` is the total for the
   **whole `date_start`–`date_end` span**, not a single day (verified: one record showed 105 hours
   across a 15-working-day span = 7 hrs/day, not 105 hours in one day). Fix: expand each leave
   record across every day in its span, sum all matching records for a given person-day FIRST,
   then cap the sum at 7 hours (a person can only be absent at most one day's worth of hours on
   any single day — mathematically equivalent to exact pro-rating without needing to compute how
   many rostered days a span covers, as long as `HoursPerDay` is uniform, which it is today).

- **Name-matching verified (2026-09-11)**: 8 sampled ConnX `Role_Name = 'Optometrist'` employees
  (Bemrose, McLeish, Nguyen, Khou, Lam, Liao, Bemrose (Colin), Anastovski) all matched an Optomate
  `USERS.FULL_NAME` row by plain substring match — no shared key between the two systems, this is
  a soft/string match, not a verified 1:1 join; edge cases (misspellings, middle names, two
  different people sharing a surname — e.g. ConnX has both "Bemrose, Colin" and "Bemrose, Trevor")
  are a known risk. **This match was only ever done once, by hand, to build the roster below — the
  SQL itself never re-verifies it. `#OptometristAppointmentDetail.OptometristIdentifier` (Optomate)
  and `@OptometristRoster.FullName` (ConnX) are never joined to each other anywhere in
  `select_Optometrist_Utilisation.sql`** — the roster only ever connects to Optomate data via
  `BranchIdentifier` + date. See "known gap" below for the consequence.
- **Roster — 10 optometrists, built into `@OptometristRoster` (2026-09-11).** Excludes 2 of the 12
  ConnX-confirmed optometrists whose employment ended before Optomate's data even starts
  (2026-02-23, the earliest `APPOINTMENT` date across all branches): Clothier, Gary (Lithgow, to
  2022-09-01) and Nguyen, Trieu (Lithgow, to 2025-07-01 — this also sidesteps needing to resolve
  his ambiguous "TC35hrs Casual" Work Pattern, since he predates the data window regardless).
  Ronald Nguyen appears as **two roster rows**, not merged, because ConnX shows him with two
  separate position segments (Optometrist to 2024-09-12, then Optometrist Lead from 2024-09-13) —
  kept separate on principle so a future schedule change on either segment isn't silently lost by
  merging, even though today's hours/days happen to be identical on both.

  | Name | Branch | Position From–To | Hours/day | Days off |
  |---|---|---|---|---|
  | Anastovski, Steve | WOL | 2026-06-09 – current | 7 | Sat, Sun |
  | Anwari, Zahra | ORA | 2023-02-06 – current | 7 | Sat, Sun |
  | Bemrose, Colin | DUB | 2025-05-01 – current | 7 | Sat, Sun |
  | Bemrose, Trevor | DUB | 2014-07-01 – current | 7 | Sat, Sun |
  | Burmi, Mukesh | LIT | 2023-09-04 – current | 7 | Sat, Sun |
  | Khou, Vincent | LIT | 2023-06-19 – current | 7 | Sat, Sun |
  | Lam, Anthony | MAK | 2024-07-08 – current | 7 | Sat, Sun |
  | Liao, Pei-Chun | ORA | 2024-07-08 – current | 7 | Sat, Sun |
  | McLeish, June | ORA | 2014-07-01 – current | 7 | Mon, Thu, Fri, Sat, Sun (Tue/Wed only) |
  | Nguyen, Ronald (Optometrist) | MAK | 2015-03-30 – 2024-09-12 | 7 | Sat, Sun |
  | Nguyen, Ronald (Lead) | MAK | 2024-09-13 – current | 7 | Sat, Sun |

**SQL status:** both `select_Clinical_Hours_Worked.sql` and `select_Optometrist_Utilisation.sql`
written and tested (2026-09-11). Test-run per-branch results (branch/day rollup across the whole
fact-table date range):

| Branch | Attended Hours | Clinical Hours Worked | Optometrist Utilisation |
|---|---|---|---|
| DUB | 504.7 | 1127.0 | 44.8% |
| LIT | 683.0 | 1728.4 | 39.5% |
| MAK | 640.5 | 1093.0 | 58.6% |
| ORA | 383.5 | 1155.0 | 33.2% |
| WOL | 64.25 | 160.0 | 40.2% |

**Bug found and fixed 2026-09-11 — METRICS-stage join fan-out inflated the denominator.** Joining
the un-rolled-up appointment fact table (many rows per branch/day — one per appointment) directly
to the denominator (one row per branch/day) and then `SUM()`-ing repeated each day's
`Clinical_Hours_Worked` once per appointment that day. Confirmed in a live run: this inflated DUB's
denominator to 9,590 hours instead of a few hundred, driving utilisation down to ~5%. Fix: roll up
the fact table to exactly one row per branch/day (`#AttendedByBranchDay`) BEFORE joining to the
denominator. The table above reflects the fix.

**Known gap — not yet resolved, makes the table above untrustworthy (found 2026-09-11, independent
review):** the numerator counts every attended appointment at a branch regardless of which
optometrist saw the patient; the denominator only has hours for the 10 roster optometrists.
`OptometristIdentifier` is present in the fact table but never used to restrict the numerator to
roster-matched optometrists, or to check how much attendance falls outside the roster. If locum
optometrists (Kathryn mentioned ~5 of them) see any patients, their appointment hours inflate the
numerator with zero offsetting denominator hours — this can only bias utilisation **upward**, by an
unknown amount. Not yet quantified: no query has been run to check what fraction of attended
appointments belong to a `USER_IDENTIFIER` outside the 10-person roster.

**Open items:**
- **Quantify the locum/non-roster attendance gap** (see above) — the single largest open risk to
  this metric's output; not yet measured.
- **Cost Centre → `BRANCH_IDENTIFIER` mapping is unverified.** Both SQL files hard-code a `CASE`
  (`'Wollongong Eye Care' → 'WOL'`, etc.) inferred by pattern, not checked against real ConnX
  `Department` values or Optomate `BRANCH.NAME`. A mismatch (extra whitespace, different naming)
  would silently drop that branch's roster/leave rows to `NULL` with no error.
- **`COUNT(*) * MAX(r.HoursPerDay)` in Layer 1 is correct today only because every roster row is 7
  hrs/day.** If any future roster entry has a different `HoursPerDay` on the same branch/day as
  others, this formula silently *overstates* the sum (e.g. 2×7 + 1×4 should be 18, formula gives
  3×7=21) with no warning. Needs to become `SUM` per person-day, not `COUNT * MAX`, before this
  can safely vary.
- **Leave-day capping assumes a uniform 7-hour rate across the entire leave span** — correct today,
  but would silently misstate hours if a leave span ever crosses a `HoursPerDay` change (e.g., a
  future roster update mid-leave) or if `HoursPerDay` becomes non-uniform.
- `Role_Name LIKE '%Optometrist%'` is not yet confirmed exhaustive against every `Role_Name` value
  present in ConnX.
- Not yet reviewed by business.

---

## Source Table Mapping (candidates confirmed by column inspection against real data)

| Area | Candidate table(s) | Key columns | Status |
|---|---|---|---|
| Appointments | `APPOINTMENT` | `STARTDATE`, `ENDDATE`, `DURATION`, `BRANCH_IDENTIFIER`, `USER_IDENTIFIER`, `APPOINTMENT_TYPE`, `PATIENTID`, `APP_PROGRESS`, `IS_BREAK` | Column structure confirmed; `APP_PROGRESS` decoded — see row below |
| Appointment types | `APPOINTMENT_TYPES` | `IDENTIFIER`, `DESCRIPTION`, `DEFAULT_DURATION` | Structure confirmed |
| Attendance status | `APPOINTMENT.APP_PROGRESS` (int, no lookup table in dbo schema) | `APP_PROGRESS IN (2,3,4,5,10)` | **Confirmed by business (Kathryn, 2026-09-10)** — full code list obtained from the Optomate front end (no DB-side lookup table exists), see decode table below. Our original data-inferred guess of `APP_PROGRESS = 5` alone was confirmed correct as far as it went, but Kathryn's Qlik logic also includes 2/3/4/10 (Waiting/Pre-test/Consulting/Dilating) as "Attended", to catch patients whose status was never updated to 5=Complete after they arrived. Implemented in `select_Script_To_Sale_Conversion.sql`. |
| Scripts / prescriptions | `SPECTACLE_RX` (glasses), `CONTACT_RX` (contact lenses, 83 rows) | `PATIENTID`, `RXDATE`, `EXAM_ID` | Both confirmed and implemented — `HasScript` checks either table (Kathryn, 2026-09-11; see decode below) |
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
| 6 | Return / credit note | 43 | 100% negative totals, avg -$493 | **Include** (business-confirmed, 2026-09-14 — previously excluded) |

### Source Table Mapping (continued)

| Area | Candidate table(s) | Key columns | Status |
|---|---|---|---|
| Locations / stores | `BRANCH` | `IDENTIFIER`, `NAME` | Confirmed — 12 branches: BAT (Bathurst), DUB (Dubbo), EME (Emerald), LIT (Lithgow), MAK (Mackay), MAR (Maroochydore), MOR (Moranbah), MUD (Mudgee), ORA (Orange), ROK (Rockhampton), TOW (Townsville), WOL (Wollongong). Most other `BRANCH` columns are third-party integration config, not relevant |
| Optometrist roster / clinical hours | `CLOCKINOUT` | `USER_IDENTIFIER`, `BRANCH_IDENTIFIER`, `IN_TIME`, `OUT_TIME` | Structure confirmed — matches "Clinical Hours Worked" concept |
| Staff / optometrist dimension | `USERS` | `IDENTIFIER`, `FULL_NAME`, `USER_TYPE`, `QUALIFICATION`, `PROVIDERNO` | **Confirmed**: `USER_TYPE = 1` = Optometrist. Verified by cross-tab against `APPOINTMENT`: all 221,600 attended appointments (`APP_PROGRESS=5`) belong to `USER_TYPE=1` users; every other `USER_TYPE` (2,3,4,5) has zero appointments, despite some also having clock-in records (front desk/dispensing/admin staff who clock in but don't see patients). **Important correction**: of the 17 `USER_TYPE=1` records, only 9 are real optometrists with actual clock-in and appointment activity (MB, TB, AL, JMC, RN, ZA, KL, SA, AG, JN — 10 total, one of which (JN) has low volume). The other 7 (`LIT`, `MAK`, `DUB`, `WOL`, `ORA` — branch placeholder accounts; `EXT` — external Rx; `CB` — inactive/admin) have zero clock-in and zero appointments and must be excluded from optometrist headcount/denominator calculations |
| Product/fee category | `INVOICE_ITEMS.STOCK_TYPE` (int, no lookup table found) | 1,2,3,4,5,7,8,9 | **Decoded from sample descriptions** (see table below). Type 7 is a mixed bucket, resolved via `ITEMCATEGORY` (see below), not per-description guessing |
| Exclusion category lookup | `ITEMCATEGORY` (`IDENTIFIER`, `NAME`, `IS_CONSULTATION`) | `IS_CONSULTATION`, `IDENTIFIER` | **Confirmed exclusion rule (Kathryn, 2026-09-10; updated 2026-09-14)**: exclude a line if `IS_CONSULTATION=1` or `IDENTIFIER IN ('REPR','WOFF','~ACC','~MIS')`. Only 4 categories have `IS_CONSULTATION=1` (`~CLC`, `~CON`, `~COT`, `~COS` — all consultation types); `REPR`/`WOFF`/`~ACC`/`~MIS` are separate identifiers with `IS_CONSULTATION=0`, added to the rule as an OR, not an AND (business's own SQL phrasing was ambiguous here — clarified in conversation) |
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
   `APP_PROGRESS IN (2,3,4,5,10)` = Attended (data-inferred `=5` guess confirmed correct by
   Kathryn, then expanded to include 2/3/4/10 per the full front-end-sourced code list — see
   decode table above).
3. ~~Verify the `EXAMINATION.ID` = `SPECTACLE_RX.EXAM_ID` = `INVOICE.EXAM_ID` join hypothesis~~ —
   done, confirmed against real data. **New finding:** an invoice exists for almost every
   completed exam (consultation fee), so "completed a purchase" must be determined from
   `INVOICE_ITEMS` line detail, not from invoice existence alone.
4. ~~Identify `INVOICE_ITEMS.STOCK_TYPE` distinct values~~ — done. ~~Resolve `STOCK_TYPE=7`
   include/exclude~~ — done, business gave the rule directly (`ITEMCATEGORY.IS_CONSULTATION=1`
   or `IDENTIFIER IN REPR/WOFF/~ACC/~MIS`) rather than reviewing the tentative per-description list;
   implemented and verified in `select_Script_To_Sale_Conversion.sql`.
5. ~~Confirm which `INVOICE.TYPE` values represent a genuinely completed sale~~ — done. TYPE 1, 2,
   5, 6 = include (TYPE 6 = return/credit note, changed from exclude to include, business-confirmed
   2026-09-14) — see decode table above.
6. ~~Confirm which `USERS.USER_TYPE` value(s) identify optometrists~~ — done, `USER_TYPE = 1`
   confirmed via appointment cross-tab (see table above).
7. ~~Confirm location dimension/grain for Chair Utilisation split~~ — done. Use
   `APPOINTMENT.BRANCH_IDENTIFIER` as the split key; only 5 of 12 `BRANCH` rows
   (DUB/LIT/MAK/ORA/WOL) actually have appointment activity.
8. ~~Confirm working-day calendar and 12–14 appointments/day assumption~~ — done. Working-day
   calendar = `COUNT(DISTINCT CAST(STARTDATE AS DATE))` per branch, fully data-derivable, no
   business input needed; the definition's "× 5 days/week" is not applied as a separate multiplier
   (it describes the assumption behind working-day counts, not an independent factor — applying it
   again would double-count). `SlotsPerDay` and `MinutesPerSlot` remain open, per-branch business
   parameters — see `@SlotConfig` in the Chair Utilisation section above; placeholders in use
   (13/day, 30 min/slot) until business confirms real values.
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
| Script-to-Sale Conversion | Complete | **Written and tested** (`select_Script_To_Sale_Conversion.sql`, 6 commits) | Add Walk-In Sales summary rollup; add side-by-side date-window comparison; get business sign-off on the finished query/results |
| Chair Utilisation | Complete | **Written and tested** (`select_Chair_Utilisation.sql`) — logic verified, results not usable until denominator is confirmed | Business: confirm `SlotsPerDay`/`MinutesPerSlot` per branch (placeholders 13/30 in use meanwhile) |
| Optometrist Utilisation | Numerator complete; denominator source changed from `CLOCKINOUT` (ruled out) to ConnX | **Written and tested** (`select_Optometrist_Utilisation.sql`, `select_Clinical_Hours_Worked.sql`) — join-fan-out bug found and fixed, but output not yet trustworthy | Quantify locum/non-roster attendance gap (numerator includes everyone, denominator only 10 roster optometrists — biases utilisation upward, unmeasured); verify Cost Centre → `BRANCH_IDENTIFIER` mapping against real ConnX data; harden `HoursPerDay` formula before it can vary per person |
