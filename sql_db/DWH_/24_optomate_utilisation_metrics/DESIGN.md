# Optomate Utilisation Metrics — DWH Design

## Overview

Explores the **Optomate** SQL Server database (separate from the Paragon/BRONZE-SILVER-GOLD
warehouse) to identify source tables supporting three optometry business metrics.

**Source system:** Optomate (SQL Server, accessed via SSMS). Access level: DML only (read/write
data), no DDL — table/object exploration and querying only, no schema changes.

**Status:** Data discovery essentially complete for all three metrics; no SQL/views written yet.

- **Script-to-Sale Conversion**: Live-data testing showed `INVOICE.EXAM_ID` cannot be used to link
  a retail purchase back to the visit that produced it — only 34% of invoices have a non-zero
  `EXAM_ID`, and of those, 2,822/2,840 are consultation-fee-only (see "Script-to-Sale reliability
  finding" below for the full investigation). **Resolved via business input (Kathryn, 2026-09-10)**:
  exact `EXAM_ID` matching was never expected to work — same-date appt/exam + sale "doesn't happen
  realistically". The correct approach is matching by **patient + date window** (same date /
  within 1 week / within 2 weeks — Qlik's version also showed 6 months, only a 1–3% difference),
  which is a business-confirmed rule, not a fabricated assumption. Grain is confirmed as **per
  purchase** (not per unique patient) — a valid script can be used for multiple purchases (glasses
  are valid for 2 years, contacts 12 months; patients commonly buy separate reading/general-wear/
  computer glasses, and one exam can produce multiple scripts in Optomate). Business also flagged
  a related useful metric: **Walk-In Sales** — purchases with no corresponding appt/script within
  the same windows (same day / 1 week / 2 weeks) — currently out of the original 3-metric scope
  but worth building alongside this one.
- **Chair Utilisation**: `APPOINTMENT` duration/status fields and the 12-branch `BRANCH` location
  dimension confirmed. The working-day calendar per branch is directly computable from
  `APPOINTMENT` data — no business input needed. **Blocked on business** only for picking a single
  value from the 12–14 appointments/day range in the "Total Available Chair Hours" formula.
- **Optometrist Utilisation**: fully ready to build. Numerator (`APPOINTMENT`, attended,
  by `USER_IDENTIFIER`), denominator (`CLOCKINOUT` in/out times), and the optometrist filter
  (`USERS.USER_TYPE=1`, excluding 7 non-person placeholder accounts) are all confirmed against
  real data.

---

## Metrics to Build

### 1. Script-to-Sale Conversion (%)

**Definition:** Patients who attended an appointment, obtained a script (prescription), and
subsequently completed a purchase ÷ relevant appointments/patients.

**Data status:** Unblocked by business input (Kathryn, 2026-09-10) after live-data testing showed
`INVOICE.EXAM_ID` is not a usable link for the exam→purchase step (see "Script-to-Sale reliability
finding" below). The appointment→exam→script portion of the chain remains confirmed reliable via
`EXAM_ID`. Purchase linkage now uses **patient + date window** matching instead, per business
confirmation that this is the expected, realistic pattern (not a fabricated workaround).

**Confirmed business rules (Kathryn, 2026-09-10):**
- **Linking a purchase to a script/exam**: same patient, purchase date within a window of the
  exam date. Report **three windows side by side**: same date, within 1 week, within 2 weeks.
  (Qlik's version also computed within 6 months as a reference point — the difference vs. 2 weeks
  was only 1–3%, so 6 months isn't necessary as a primary cut but can be added if useful.)
  Same-date matching essentially never fires in practice ("doesn't happen realistically") — the
  1-week/2-week windows are the meaningful ones.
- **True conversion definition**: appointment/exam + script record + sale (frame/sunglasses +
  lenses) — matches our original 3-part definition. Business also wants a breakdown showing
  appointments/exams **with** a script vs **without** one (as their Qlik version did), since not
  every exam is expected to produce a script.
- **Statistical grain: per purchase, not per unique patient.** A single script commonly supports
  *multiple* purchases — reading glasses, general-wear glasses, and computer glasses are often
  bought separately from one prescription; a script is valid 2 years (contacts: 12 months); and
  Optomate (unlike the previous system, NetOptic) allows one exam to generate multiple scripts
  (reading / multifocal / distance). Business also noted WF members with extras cover are commonly
  advised to purchase one pair per year to maximise their optical/sunglass benefit — multiple exams
  within 2 years usually only happens for patients with more complex eye issues. **This overturns
  our earlier "per-patient" hypothesis** (see reliability finding below) — that hypothesis assumed
  glasses are a rarely-repeated purchase, which business confirmed is not correct.
- **New related metric requested — "Walk-In Sales"**: purchases with NO corresponding appt/script
  within the same windows (same day / 1 week / 2 weeks). These represent unexpected/unplanned
  retail sales and are useful alongside the conversion metric. Not part of the original 3-metric
  scope, but worth building as a natural by-product of the same query logic.

**Open items:**
- Exact include/exclude rule for `STOCK_TYPE = 7` line items (Drops, dry-eye care products,
  service fees) — see breakdown below. Still pending business sign-off, independent of the linking
  question above.
- Implementation: rewrite `select_Script_To_Sale_Conversion.sql` to match purchases by
  patient + date window (same day / 1 week / 2 weeks) instead of `EXAM_ID`, output all three
  windows side by side, and add the Walk-In Sales breakdown.

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
     produced them. The metric's numerator cannot be built from `EXAM_ID` alone — doing so
     undercounts genuine conversions by roughly two orders of magnitude, not because sales aren't
     happening (`INVOICE_ITEMS` has thousands of genuine retail lines) but because the database
     doesn't record which exam/visit they came from.
   - **Resolved by business**: linking by "same patient + purchase within N days of the exam" was
     initially considered and rejected internally as an unfounded fabrication with no FK-level
     evidence. Business has since confirmed this is in fact the correct, expected approach — exact
     same-date/EXAM_ID linkage was never realistic — and specified the exact windows to use (same
     date / 1 week / 2 weeks). This is now a business-confirmed rule, not an assumption.

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
| Attendance status | `APPOINTMENT.APP_PROGRESS` (int, no lookup table found in dbo schema) | `APP_PROGRESS = 5` | **Inferred from data, not a documented lookup**: cross-tabbed against `INVOICE` (same patient + same calendar day) — of 6,266 appointments with `APP_PROGRESS=5`, 6,232 (99.5%) had a same-day invoice, vs. 2/4,492 (0.04%) for `APP_PROGRESS=0`. Treating `APP_PROGRESS = 5` as "Attended" for all three metrics. Other codes (1,2,4,6,7,8,11,12,13,16,18,19) are low-volume and not yet decoded individually — not needed while attended/not-attended is a binary split |
| Scripts / prescriptions | `SPECTACLE_RX` (glasses), `CONTACT_RX` (contact lenses, 82 rows) | `PATIENTID`, `RXDATE`, `EXAM_ID` | Structure confirmed for `SPECTACLE_RX`; need to confirm whether contact lens scripts count too |
| Exam link (appointment↔script↔sale) | `EXAMINATION` | `ID`, `PATIENT_ID`, `EXAM_DATE`, `COMPLETED`, `FINALISED` | **Verified**: `EXAMINATION.ID` = `SPECTACLE_RX.EXAM_ID` = `INVOICE.EXAM_ID` join confirmed against real data (20-row sample, all `COMPLETED=1` exams). `SPECTACLE_RX` is present for ~13/20 exams (script is optional, not automatic) |
| Sales / purchases | `INVOICE`, `INVOICE_ITEMS` | `INVOICE.PATIENTID`, `SALE_DATE`, `EXAM_ID`, `TYPE`; `INVOICE_ITEMS.DESCRIPTION`, `STOCK_TYPE`, `QTY`, `EXTENDED` | **Important correction from data**: an `INVOICE` is generated for almost every completed `EXAMINATION` (consultation fee), so presence of an `INVOICE` alone does NOT mean a retail purchase happened. "Completed a purchase" must be judged from `INVOICE_ITEMS` line detail (see `STOCK_TYPE` decode below) |

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
| Product/fee category | `INVOICE_ITEMS.STOCK_TYPE` (int, no lookup table found) | 1,2,3,4,5,7,8,9 | **Decoded from sample descriptions** (see table below). Type 7 is a mixed bucket needing description-level splitting |
| Exclusion categories (e.g. Drops) | `INVOICE_ITEMS.STOCK_TYPE = 7` filtered by `DESCRIPTION` | e.g. "Optimed Xailin Night" | Full distinct `DESCRIPTION` list for type 7 pulled (41 distinct values, see below) — **pending business decision on exact inclusion/exclusion rule per line** |

### `INVOICE_ITEMS.STOCK_TYPE` decode (from sampled descriptions, not an official lookup)

| STOCK_TYPE | Meaning | Count | Use in metrics |
|---|---|---|---|
| 1 | Consultation fee (Initial/Subsequent/Brief Consultation) | 3,158 | **Exclude** — exam fee, not a retail purchase |
| 2 | Spectacle frames (e.g. AVANTI, LACOSTE) | 2,042 | Include as purchase |
| 3 | Sunglasses frames (e.g. RAY-BAN, UGLY FISH) | 1,345 | Include as purchase |
| 4 | Spectacle lenses (e.g. ZEISS, Synchrony) | 3,150 | Include as purchase |
| 5 | Contact lenses (e.g. CooperVision, Alcon, J&J) | 104 | Include as purchase |
| 7 | Mixed: eye health checks, drops/ointments, fitting fees, repairs, freight, write-offs, accessories | 2,334 | **Needs description-level split — pending business decision**, see full breakdown below |
| 8 | Lens coatings (e.g. ZEISS DuraVision AR coating) | 1,044 | Include as purchase (lens add-on) |
| 9 | Lens tints (e.g. ZEISS Tint Gradient/Solid) | 61 | Include as purchase (lens add-on) |

### `STOCK_TYPE = 7` full description breakdown (pending business call on which count as "Drops"/exclusions)

| Description | Count | Tentative category (not yet confirmed by business) |
|---|---|---|
| Eye Health Checks (inc. OCT, CT, RP &/or ODC) | 1,415 | Exam-like — likely exclude |
| Own Frame Fitting Fee | 295 | Service fee |
| Xailin Eye Drops 10mL | 108 | Drops — likely exclude |
| Own Frame | 98 | Service fee |
| Replacement Part/Repair to Frame | 59 | Repair service |
| Optimed Xailin Gel | 50 | Drops/gel — likely exclude |
| Standard Freight | 44 | Freight |
| Rohto Dry Eye Aid Drops | 40 | Drops — likely exclude |
| Optimed Blephadex Lid Cleansing Foam | 37 | Dry-eye care product — TBC |
| Xailin Gel 10g tube | 27 | Drops/gel — likely exclude |
| Zeiss Lens Cleaning Wipes | 23 | Accessory |
| Express Freight | 20 | Freight |
| Manuka Eye Drops - 10ml | 15 | Drops — likely exclude |
| Optimed Blephadex Manuka Honey Wipes | 11 | Dry-eye care product — TBC |
| Write Off Non-Taxable Items | 10 | Financial adjustment — exclude |
| Write Off Taxable Items | 9 | Financial adjustment — exclude |
| Xailin Hydrate (10mL) | 8 | Drops — likely exclude |
| Optimed Xailin Night | 6 | Drops/ointment — likely exclude |
| Optimed Bruder Eye Hydrating Compress (Double Eye) | 6 | Dry-eye care product — TBC |
| Nylon Cord - Neck Chain | 6 | Accessory |
| Opening Balance (From NetOptic) | 6 | Financial adjustment — exclude |
| Optimed Blephadex Pro with Manuka Honey - 30 pc Wipes | 5 | Dry-eye care product — TBC |
| Optimel Manuka + Eyelid Cream - For Dry eyes, Blepharitis & MGD (2024) | 5 | Dry-eye care product — TBC |
| Avenova Eyelid Spray 40ml - For Dry eyes, styes, Blepharitis & MGD (2024) | 4 | Dry-eye care product — TBC |
| D.E.R.M - Full Eye Mask - Dry Eye Relief (2024) | 3 | Dry-eye care product — TBC |
| Optimed Blephadex Eye Lid Foam Cleanser | 3 | Dry-eye care product — TBC |
| Optimed Blephadex Pro CLEANSE Wipes with Manuka UMF 10+ & Dead Sea Salt | 2 | Dry-eye care product — TBC |
| General Accessory Item | 2 | Accessory |
| Optimed Xailin Hydrate | 2 | Drops — likely exclude |
| Zeiss Anti-Fog Kit - Contains spray and cleaning cloth | 2 | Accessory |
| Zeiss Lens Cleaning Wipes (50 wipes) | 2 | Accessory |
| Zocular Eyelid Cleaner/Foam Pump 50ml- For General Blepheritis | 2 | Dry-eye care product — TBC |
| Xailin Gel (10g) | 1 | Drops/gel — likely exclude |
| Pocket Case | 1 | Accessory |
| Repair/Replace temple | 1 | Repair service |
| Good Optical Hilco Lens Wipes | 1 | Accessory |
| Good Optical OCuSOFT Lid Scrub | 1 | Dry-eye care product — TBC |
| FRAMECARE - REPAIR | 1 | Repair service |
| Celluvisc Unit Dose (30 x 0.4ml) | 1 | Drops — likely exclude |
| CLICKONS_ Click ons | 1 | Accessory |
| Nose Pads | 1 | Accessory |

**Note:** categories above are tentative groupings to aid a business conversation, not a
finalised rule. The actual include/exclude decision per line must come from business.

---

## Open Questions / Next Steps

1. ~~List all schemas/tables in Optomate~~ — done (dbo schema, ~280 tables).
2. ~~Inspect appointment table structure~~ — done. ~~Decode `APPOINTMENT.APP_PROGRESS`~~ — done,
   `APP_PROGRESS = 5` = Attended (inferred via same-day invoice cross-tab, see table above).
3. ~~Verify the `EXAMINATION.ID` = `SPECTACLE_RX.EXAM_ID` = `INVOICE.EXAM_ID` join hypothesis~~ —
   done, confirmed against real data. **New finding:** an invoice exists for almost every
   completed exam (consultation fee), so "completed a purchase" must be determined from
   `INVOICE_ITEMS` line detail, not from invoice existence alone.
4. ~~Identify `INVOICE_ITEMS.STOCK_TYPE` distinct values~~ — done, decoded via sampled
   descriptions. ~~Pull full `STOCK_TYPE = 7` description list~~ — done, 41 distinct descriptions
   captured with tentative groupings (see breakdown above). **Blocked on business**: need
   business to confirm the final include/exclude call per description group (Drops, dry-eye care
   products, service fees, freight, accessories, write-offs).
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
   business (Kathryn, 2026-09-10)**: use patient + date window matching instead (same date / 1
   week / 2 weeks), confirmed as the expected, realistic approach. See "Script-to-Sale
   reliability finding" above and the confirmed business rules in the metric section.
10. **NEW — grain confirmed as per purchase**, not per unique patient (business overturned our
    earlier per-patient hypothesis — see metric section for reasoning).
11. **NEW — build "Walk-In Sales" as a related metric** (purchases with no appt/script match in
    any window) — business-requested, natural by-product of the same query logic.

## Summary: what's left before SQL can be finalised

| Metric | Data exploration | Blocking item | Can write SQL now? |
|---|---|---|---|
| Script-to-Sale Conversion | Complete — purchase linking rule now confirmed by business (patient + date window: same day / 1 week / 2 weeks) | Business: `STOCK_TYPE=7` exclusion list only | Yes — rewrite `select_Script_To_Sale_Conversion.sql` to use date-window matching instead of `EXAM_ID`; use a placeholder `STOCK_TYPE=7` exclusion list pending sign-off |
| Chair Utilisation | Complete | Business: pick one value from the 12–14 appointments/day range | Yes — with a placeholder value (e.g. 13), clearly flagged as provisional |
| Optometrist Utilisation | Complete | None | Yes — no placeholders needed |

All three metrics are now unblocked for SQL implementation. Script-to-Sale Conversion's query
needs a rewrite (date-window matching replaces `EXAM_ID` matching, grain changes to per-purchase,
and a Walk-In Sales breakdown should be added) rather than a small edit, since the linking
mechanism itself changed.
