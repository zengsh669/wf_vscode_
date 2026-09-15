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

**Definition:** Attended Appointment Duration (hours) ÷ Clinical Hours Worked, split into an
optometrist share and a locum share.

**Design superseded 2026-09-15 (business-confirmed) — fixed branch capacity, no roster headcount,
no `USER_APP_ADJUST` layer.** The original design (below, kept for history) computed the
denominator from a hand-matched roster headcount and later added a third layer reading
`USER_APP_ADJUST.INACTIVE=1` to catch no-shows. Both were abandoned:
- The roster-headcount Layer 1 broke down once `USER_APP_ADJUST` testing surfaced branch/day rows
  with far more "inactive" hours than the roster said were ever available (e.g. MAK showed 26
  inactive hours against a 14-hour theoretical capacity) — root cause: `USER_APP_ADJUST` records
  belong to Optomate `USER_IDENTIFIER`s (via `USERS`), not to the ConnX roster, so it freely
  includes locums and other non-rostered staff. Filtering it down to only the 10 rostered names
  required a ConnX-name ↔ Optomate-identifier mapping that turned out to be incomplete and
  partly wrong (see below) — the whole approach was judged too fragile to keep patching.
- **Business's actual mental model, once asked directly**: each branch has a **fixed clinical
  capacity per day** — 7 hours for a single-optometrist branch, 14 hours for ORA (two positions) —
  that does **not** shrink when the rostered optometrist is away, because a locum covers the gap.
  Locums are highly mobile (not tied to one branch, not on a clean HR record) and are deliberately
  **not tracked individually** — only the rostered optometrists' leave is tracked from ConnX.

**Current design (`select_Clinical_Hours_Worked.sql`, re-embedded in
`select_Optometrist_Utilisation.sql`), business-confirmed 2026-09-15:**

- **`@BranchCapacity`** — a fixed hours/day constant per branch: DUB/MAK/LIT/WOL = 7 (one
  optometrist position), ORA = 14 (two positions: Anwari, Zahra + McLeish, June). Not derived from
  headcount — a flat business number.
- **`@OptometristRoster`** — trimmed to the **6 rostered optometrists only** (no locums), each with
  a confirmed Optomate `Identifier` (see table below):

  | Name | Identifier | Branch | Position From–To | Hours/day | Days off |
  |---|---|---|---|---|---|
  | Anastovski, Steve | SA | WOL | 2026-06-09 – current | 7 | Sat, Sun |
  | Anwari, Zahra | ZA | ORA | 2023-02-06 – current | 7 | Sat, Sun |
  | Bemrose, Trevor | TB | DUB | 2014-07-01 – current | 7 | Sat, Sun |
  | Burmi, Mukesh | MB | LIT | 2023-09-04 – current | 7 | Sat, Sun |
  | McLeish, June | JMC | ORA | 2014-07-01 – current | 7 | Mon, Thu, Fri, Sat, Sun (Tue/Wed only) |
  | Nguyen, Ronald (Optometrist) | RN | MAK | 2015-03-30 – 2024-09-12 | 7 | Sat, Sun |
  | Nguyen, Ronald (Lead) | RN | MAK | 2024-09-13 – current | 7 | Sat, Sun |

  Dropped from the old 10-person roster: Bemrose, Colin; Lam, Anthony; Liao, Pei-Chun — all
  confirmed (2026-09-14, via `USER_APP_ADJUST` investigation) to be **locums**, not rostered staff
  — `select_Clinical_Hours_Worked.sql`'s header has the full reasoning. **Khou, Vincent** — still
  unconfirmed against `USERS` (no matching `IDENTIFIER` found under "Khou") — dropped from the
  roster for now since he never appears with an `INACTIVE=1` row in `USER_APP_ADJUST`, so his
  absence from the roster doesn't currently affect any calculation; needs resolving before any
  future feature relies on a complete 7-person LIT/ORA roster.

- **Layer 1 — fixed capacity.** `Theoretical_Available_Hours` = `@BranchCapacity` on every working
  day (day with ≥1 attended appointment at that branch — unchanged definition). Replaces the old
  roster-headcount multiplication entirely.
- **Layer 2 — rostered optometrist's leave only, on days they were actually rostered.**
  `#RosteredWorkingDays` marks, per person/day, whether that day falls in their `PositionFrom`–
  `PositionTo` window and is not one of their `DaysOff` — e.g. McLeish's Mon/Thu/Fri were never
  "hers" to begin with, so a leave record spanning one of those days can't count as her leave.
  ConnX leave (`q2vEmployeeLeaveHistory`) is matched only against those rostered days, summed per
  person/day, then capped at `HoursPerDay` (unchanged capping logic from the original design, still
  correct: verified against a real 35-hour/7-day span record for Anwari, Zahra covering
  2026-09-07–13, which — because she was rostered on the resulting working days that week — capped
  correctly to her `HoursPerDay` each day rather than needing manual pro-rating; see
  `select_Clinical_Hours_Worked.sql` git history for the trace).
- **Output columns, all shown for visibility, not double-subtracted:**
  - `Theoretical_Available_Hours` — the fixed branch capacity for that day.
  - `Optom_Not_Scheduled_Hours` = capacity − (hours actually rostered that day) — the
    **structural** gap (e.g. ORA on McLeish's day off: only Anwari's 7 of the 14 hours were ever
    rostered).
  - `Total_Leave_Hours` — the **leave** gap (rostered but absent).
  - `Clinical_Hours_Worked` = `Theoretical_Available_Hours`, **unchanged** — leave is NOT
    subtracted here (2026-09-15 fix — see below for why).

**Why `Clinical_Hours_Worked` doesn't subtract leave (bug found and fixed 2026-09-15):** the first
version of this redesign *did* subtract `Total_Leave_Hours` from capacity, mirroring the original
two-layer design. That produced `Optometrist_Utilisation > 100%` for MAK (211% — 652 attended hours
÷ a 308.5-hour denominator that had been shrunk by leave) because the **numerator never shrinks**
when the optometrist is on leave — the locum's appointments still count as attended hours, but
their capacity had been subtracted away instead of counted. Fix: `Clinical_Hours_Worked` is the
fixed capacity, full stop; `Optom_Not_Scheduled_Hours`/`Total_Leave_Hours` are informational only.

**Optom/locum split (added 2026-09-15), METRICS stage in `select_Optometrist_Utilisation.sql`:**
business's model is that the optometrist has first claim on attended hours, up to their own
denominator; any overflow goes to the locum, up to the locum's denominator — but **only when a
locum denominator actually exists**. Per branch/day:
- `Optom_Denominator_Hours` = `Clinical_Hours_Worked` − (`Optom_Not_Scheduled_Hours` +
  `Total_Leave_Hours`).
- `Locum_Denominator_Hours` = `Optom_Not_Scheduled_Hours` + `Total_Leave_Hours`.
- If `Locum_Denominator_Hours = 0` (optometrist fully rostered, no leave that day): **all**
  attended hours go to `Optom_Attended_Hours`, even if that exceeds their denominator — a small
  overrun with zero locum coverage available is the optometrist working overtime, not a locum
  appearing from nowhere (bug found and fixed 2026-09-15: the first version of this split forced
  the overrun onto `Locum_Attended_Hours` regardless, which made no sense against a
  `Locum_Denominator_Hours` of 0).
- Otherwise: `Optom_Attended_Hours` = `MIN(attended hours, Optom_Denominator_Hours)`;
  `Locum_Attended_Hours` = whatever's left over (0 if optom's denominator alone covers everything).
- **Deliberately not capped at 100%** — `Optom_Utilisation_Pct`/`Locum_Utilisation_Pct` (rolled up
  per branch in output 3) can exceed 100% on purpose, to surface genuine overload instead of
  hiding it behind a clamp.
- Split is **day-granularity only**, not per-appointment — deliberate scope decision: if a 7-hour
  day has 4 hours from the optometrist and 3 from a locum, this design can't currently tell which
  specific appointments were whose (that would need per-appointment `OptometristIdentifier`
  attribution, a finer-grained analysis not built here) — day-level totals are what the business
  question actually needs.

**Output structure, `select_Optometrist_Utilisation.sql`:**
1. Raw `#OptometristAppointmentDetail` fact table (unchanged from the original design).
2. Per branch/day: attended hours, capacity, the two gap columns, both denominators, and the
   optom/locum attended-hours split — **no percentages here**.
3. Rolled up per branch (whole date range): `Optometrist_Utilisation` (overall, unsplit — original
   metric, unchanged formula) plus `Optom_Utilisation_Pct` and `Locum_Utilisation_Pct`.

**Test-run results (2026-09-15, after both fixes):**

| Branch | Attended Hours | Clinical Hours Worked | Optometrist Utilisation | Optom Util % | Locum Util % |
|---|---|---|---|---|---|
| DUB | 516.7 | 595 | 86.8% | 86.7% | 88.6% |
| LIT | 687.8 | 931 | 73.9% | 77.4% | 47.5% |
| MAK | 652.0 | 819 | 79.6% | 78.2% | 80.5% |
| ORA | 387.8 | 1148 | 33.8% | 56.3% | 9.5% |
| WOL | 66.75 | 175 | 38.1% | 38.4% | 0% |

ORA's low `Locum Util %` (9.5%) against a comparatively large locum denominator (McLeish's
part-week roster leaves a lot of structural gap) means the two rostered optometrists are covering
most of ORA's load between them, with locums rarely needed — worth flagging to business as a
finding, not a bug.

**Open items:**
- **Khou, Vincent's Optomate `USER_IDENTIFIER` still unresolved** — doesn't block current output
  (see roster table above) but should be resolved before LIT/ORA roster changes are trusted blind.
- **Cost Centre → `BRANCH_IDENTIFIER` mapping is unverified** (unchanged from original design) —
  both SQL files hard-code a `CASE` (`'Wollongong Eye Care' → 'WOL'`, etc.) inferred by pattern,
  not checked against real ConnX `Department` values or Optomate `BRANCH.NAME`.
- `Role_Name LIKE '%Optometrist%'` is not yet confirmed exhaustive against every `Role_Name` value
  present in ConnX.
- Not yet reviewed by business.

<details>
<summary>Superseded design history (roster-headcount denominator + USER_APP_ADJUST Layer 3,
2026-09-11 to 2026-09-14 — kept for context, no longer in the SQL)</summary>

**`CLOCKINOUT` (Optomate) ruled out (2026-09-11): systemic data-quality issues.**
- `IN_TIME`/`OUT_TIME` are `TIME`-only columns (no date) — the date must come from `TIMESTMP`
  (verified: `CAST(TIMESTMP AS DATE)` matches `CAST(DATE_ADDED AS DATE)` for 100% of rows).
- Same-optometrist-same-day multiple records are common: of all same-day gaps between consecutive
  clock-ins, 401 were under 15 minutes (likely duplicate/system-generated), 132 were 15–60 minutes,
  and only 310 were over 60 minutes (a plausible real gap between shifts).
- Root cause: a single clock-in action appears to write one row **per branch the employee has
  access to** — confirmed to affect real, confirmed optometrists too (SA, MB both showed
  multi-branch same-day clock records). Decision: abandon `CLOCKINOUT` for this metric.

**Original two-layer ConnX denominator (2026-09-11):** Layer 1 multiplied a rostered headcount
(`COUNT(*) * MAX(HoursPerDay)`) by working days instead of using a fixed branch constant; Layer 2's
leave-capping logic was the same as today's. Name-matching between ConnX and Optomate was verified
once by hand for 8 sampled employees, never re-verified in SQL.

**METRICS-stage join fan-out bug (found and fixed 2026-09-11):** joining the un-rolled-up
appointment fact table directly to the once-per-branch/day denominator and `SUM()`-ing inflated
DUB's denominator to 9,590 hours instead of a few hundred. Fixed by rolling up to one row per
branch/day before the join — this fix carried forward into the current design unchanged.

**`USER_APP_ADJUST` Layer 3 (added, then removed, 2026-09-14 to 2026-09-15):** added to subtract
confirmed no-show hours (`INACTIVE=1`) from the roster-headcount denominator. Investigating a
resulting negative denominator at MAK (26 inactive hours against 14 theoretical hours) traced back
to non-rostered `USER_IDENTIFIER`s (locums, and some entirely unrelated accounts) appearing in
`USER_APP_ADJUST` with no corresponding roster capacity to subtract from. Attempts to fix this by
filtering to only rostered names (via a ConnX-name ↔ Optomate-identifier join) surfaced further
data problems — Liao, Pei-Chun's `USERS.BRANCH_IDENTIFIER` disagreed with her ConnX-rostered branch
(MAK vs. ORA), Bemrose, Colin had no `BRANCH_IDENTIFIER` recorded at all — and ultimately led to
business clarifying that the fixed-capacity model (above) was the correct mental model all along,
making the entire `USER_APP_ADJUST` layer unnecessary.

</details>

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
| Optometrist Utilisation | Numerator complete; denominator redesigned 2026-09-15 to fixed branch capacity (business-confirmed), replacing the roster-headcount + `USER_APP_ADJUST` approach | **Written and tested** (`select_Optometrist_Utilisation.sql`, `select_Clinical_Hours_Worked.sql`) — optom/locum split added; fan-out bug and the negative-denominator/>100%-utilisation bugs found and fixed | Resolve Khou, Vincent's Optomate `USER_IDENTIFIER`; verify Cost Centre → `BRANCH_IDENTIFIER` mapping against real ConnX data; business review of the new fixed-capacity model and results |
