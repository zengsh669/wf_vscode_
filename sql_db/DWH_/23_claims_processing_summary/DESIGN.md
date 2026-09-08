# Claims Processing Summary — DWH Design

## Overview

Translates the QlikSense load script `claims_processing.md` into a SQL Server SILVER layer.

**Source system:** paragon (BRONZE.dbo — SQL Server ODS mirror of Paragon) plus QVD extracts on prdqs01_atobi.

**Output scope (confirmed with user):** This project's deliverable is a single **pure `SELECT ... FROM ...`
query** replicating the `Claims` logic — no `CREATE TABLE`, no stored procedure, no
TRUNCATE+INSERT. This is a deliberate scope boundary, not an oversight:

1. **Runtime** — the query joins 21 BRONZE tables across 17 sequential transformation stages;
   it is not something end users should run ad hoc or something that should live behind a
   frequently-executed stored procedure without further optimisation.
2. **Mixed table/view sourcing** — several BRONZE objects (`ClaimDetailGenAndHosp`,
   `ClaimDetailsAtService`, `ClaimsByChannel`) may be views rather than base tables (unverified,
   see [Source Table Mapping](#source-table-mapping-confirmed)), which complicates indexing/
   materialisation decisions that belong with whoever owns those objects, not with this project.

**Ownership:** the BRONZE tables/views this query reads from are provided and maintained by
**Hippo** (external vendor). The user's responsibility ends at delivering a *correct* `SELECT`
query; converting it into a directly-queryable, performant table or view (optimisation, indexing,
materialisation strategy, refresh cadence) is Hippo's responsibility, not this project's. The
final `Total` summary table (Qlik lines 647–771) is also out of scope — see
[Objects NOT Built](#objects-not-built).

**Status:** `select_Claims.sql` drafted and reviewed across 11 static verification passes (44
findings fixed, 1 additional finding raised in pass 10 and explicitly declined by the user). **Not
yet executed against a live database** — see [Open Questions / Next Steps](#open-questions--next-steps).

---

## Architecture

```
BRONZE.dbo (read-only)                          SILVER
──────────────────────────                      ─────────────────
claim_status_type            ──┐
person                         │
provider                       │
provider_claim_status_type     │
claim                          │
ClaimsByChannel                ├──→   Claims (wide intermediate table)
till                           │
grouping                       │
MemberCorrespondance           │
claim_status                   │
provider_claim_status          │
claim_alloc                    │
provider_claim_alloc           │
ClaimDetailGenAndHosp          │
provider_number                │
ClaimDetailsAtService           │
item                            │
operator                        │
claim_generalitem               │
MemberCover                     │
MemberAgent                   ──┘

(Total summary table NOT built this pass — would read from SILVER.dbo.Claims if added later)
```

---

## Source Table Mapping (confirmed)

All BRONZE tables live in `BRONZE.dbo`.

| Qlik reference | Type | BRONZE table | Notes |
|---|---|---|---|
| `paragon.dbo."claim_status_type"` | SQL table | `claim_status_type` | |
| `paragon.dbo."person"` | SQL table | `person` | Daily snapshot tables also exist (`person_20260803` … `person_20260907`); confirmed to use the un-suffixed current table |
| `paragon.dbo."provider"` | SQL table | `provider` | Used both as ProviderMap source (skipped, see below) and in the adjustments query join |
| `paragon.dbo.provider_claim_status_type` | SQL table | `provider_claim_status_type` | |
| `paragon.dbo."claim"` | SQL table | `claim` | Loaded 3x for different mappings (BucketTypeMap, MembershipIDMap, TillMap) |
| `paragon.dbo."ClaimsByChannel"` | SQL table | `ClaimsByChannel` | Name suggests a possible view/pre-joined object; not verified, does not affect SQL usage |
| `paragon.dbo."till"` | SQL table | `till` | |
| `grouping` (joined in TillNameMap) | SQL table | `grouping` | Also used via QVD (Paragon_Grouping.qvd) — same underlying table |
| `MemberCorrespondance` | SQL table | `MemberCorrespondance` | |
| `paragon.dbo."claim_status"` | SQL table | `claim_status` | Main Claims table + 3 further loads (Verified/Received/Paid) + MaxClaimStatusOther subquery |
| `paragon.dbo."provider_claim_status"` | SQL table | `provider_claim_status` | Concatenated into Claims (provider path) + MaxClaimStatusProvider subquery |
| `paragon.dbo."claim_alloc"` | SQL table | `claim_alloc` | Gen/Hosp bucket allocation |
| `paragon.dbo."provider_claim_alloc"` | SQL table | `provider_claim_alloc` | Provider bucket allocation |
| `ClaimDetailGenAndHosp` | SQL table | `ClaimDetailGenAndHosp` | Name suggests a possible view/pre-joined object; not verified, does not affect SQL usage |
| `provider_number` | SQL table | `provider_number` | Joined in adjustments query |
| `ClaimDetailsAtService` | SQL table | `ClaimDetailsAtService` | Name suggests a possible view/pre-joined object; not verified, does not affect SQL usage |
| `item` | SQL table | `item` | Joined in adjustments query |
| `Paragon_Operator.qvd` | QVD | `operator` | OperatorMap, OperatorMapping |
| `Paragon_Grouping.qvd` | QVD | `grouping` | Same table as SQL `grouping` above |
| `Paragon_Person.qvd` | QVD | `person` | Same table as SQL `person` above (PersonNameMap) |
| `Paragon_Claim_GeneralItem.qvd` | QVD | `claim_generalitem` | Manual Claim flag; table name has no underscore separator, confirmed via keyword search |
| `Paragon_MemberCover.qvd` | QVD | `MemberCover` | Current Product; initial `LIKE '%cover%'` search missed it — confirmed by direct name lookup |
| `Paragon_MemberAgent.qvd` | QVD | `MemberAgent` | Current Agent; initial `LIKE '%agent%'` search missed it — confirmed by direct name lookup |

### Skipped (dead code — confirmed with user)

| Qlik Mapping table | Source | Reason |
|---|---|---|
| `ItemMap` | `Paragon_item.qvd` | Only reference (line 500) is commented out; `[Item Description]` is sourced directly from the SQL query instead |
| `PersonMap` | `paragon.dbo.person` | Defined but never referenced via `ApplyMap()` anywhere in the script |
| `ProviderMap` | `paragon.dbo.provider` | Defined but never referenced via `ApplyMap()` anywhere in the script |
| `BucketMap` | `paragon.dbo.claim_alloc_reason` | Defined but never referenced via `ApplyMap()` anywhere in the script |
| `DepartmentMap` | `paragon.dbo.department` | Defined but never referenced via `ApplyMap()` anywhere in the script |

`claim_alloc_reason` and `department` were therefore never verified to exist in BRONZE (not needed since the mapping tables that use them are skipped).

---

## Output Query

### `Claims` (pure SELECT, not a table)

A single SELECT query (CTEs), built as 17 sequential CTE stages mirroring the Qlik Resident LOAD
chain (`Claims` → `OperatorCheck` → `BringTogether` → cohort IntervalMatch → `DaysTilPaid` →
adjustments join → `AdjustedOperator` → `String` → `Branch` → `OperatorBranch` → `Audit`; see the
`Stage 1`–`Stage 17` comments in `select_Claims.sql` for the exact breakdown).

**Data sources:** see [Source Table Mapping](#source-table-mapping-confirmed) above — 21 BRONZE
tables feed into this single query.

**Key columns:** ~40+ columns across 17 transformation stages. Not enumerated in full here — the
SQL itself (built stage-by-stage as CTEs mirroring the Qlik Resident chain) is the source of truth
for the final column list. Confirmed BRONZE column types for the core join/date/operator columns
(via `INFORMATION_SCHEMA.COLUMNS`):

| Column | Table(s) | Type |
|---|---|---|
| `claim_id` | claim, claim_status, claim_alloc | `DECIMAL(9,0)` |
| `provider_claim_id` | provider_claim_status, provider_claim_alloc | `DECIMAL(9,0)` |
| `membership_id` | claim | `DECIMAL(9,0)` |
| `claim_status_type` | claim_status | `CHAR(1)` |
| `provider_claim_status_type` | provider_claim_status | `CHAR(1)` |
| `claim_status_version` | claim_status, provider_claim_status | `DECIMAL(3,0)` |
| `status_date` | claim_status, provider_claim_status | `DATETIME` |
| `create_datetime` / `update_datetime` | all claim_status-family tables | `DATETIME` |
| `create_operator` / `update_operator` | all claim_status-family tables | `CHAR(16)` |
| `till_id` | claim | `CHAR(10)` |
| `oper_name` | operator, claim_alloc, provider_claim_alloc | `CHAR(16)` / `CHAR(10)` (inconsistent width across tables) |
| `first_name` / `surname` | operator, person | `VARCHAR(40)` |
| `claim_alloc_reason_id` | claim_alloc, provider_claim_alloc | `INT` |
| `department_id` | operator | `DECIMAL(9,0)` |

**Known Qlik source quirk (kept as-is per user instruction — faithful to Qlik logic):**
Line 218, field `[Received Year]`, computes `date(floor(status_date))` — the same expression as
the preceding `[Received Status Date]` field, NOT `year(status_date)`. This looks like a
copy-paste artifact in the original Qlik script (the field name says "Year" but the value is a
date). User confirmed: replicate faithfully, do not "fix" it.

**Generated file:**
- `select_Claims.sql` — standalone, runnable `SELECT` statement. No `CREATE TABLE`,
  no stored procedure, no persistence — that decision belongs to whoever owns the downstream table.
  Status: drafted, independently reviewed, all findings fixed. **Not yet run** —
  needs execution to confirm it actually compiles and returns sane data.
  Table references are **unqualified** (`dbo.xxx`, no `BRONZE.` prefix) — intended to run directly
  against the production database, with that database set as the current context (`USE`, or via
  the connection). If run from a client where BRONZE is a separate linked database, the `dbo.`
  prefix alone won't resolve — reintroduce the database prefix in that case.

**Deliberate Qlik-bug replications (Principle 1 — confirmed with user, not silently "fixed"):**
- `[Claim Operator]` (main claim_status load): Qlik wraps the Verified/create-operator logic in
  `isnum(...)` — if the resolved operator code looks numeric, the output is the literal string
  `'Web/Mobile Claim'` instead. Kept as-is (business-meaningful, not a bug).
- `FinalOperatorLookupCode` (feeds `[Final Operator]`/`AssessedOperatorCheck`/`VerifiedOperatorCheck`):
  Qlik line 327 has `len(update_operator>0)`, which parses as `LEN(update_operator > 0)` — length of
  a boolean, always truthy. So in the original Qlik script this branch **always** resolves to
  `update_operator`, never falls through to `[ClaimOperator]`. Replicated as always-true (i.e. the
  SQL uses `update_operator` unconditionally), matching Qlik's actual (buggy) behaviour rather than
  the "intended" conditional logic.

**Independent review findings (all fixed) — see `select_Claims.sql` inline comments for detail:**
1. Three OperatorCheck left-joins (Verified/Assessed/Paid) were missing `[Membership ID]` as a
   join key — Qlik auto-joins Left Join on ALL identically-named fields, not just `[Claim ID]`.
   Fixed by adding `[Membership ID]` (and `[Verified Status Date]` for the Verified join
   specifically) to each CTE and the join predicate.
2. `[Verified Check]` output field (Qlik lines 322-325) was missing entirely — added.
3. `PaidStatus`, `[PaidStatusDate]`, `[VerifiedStatusDate]`, `[AssessedStatusDate]` were computed
   in Stage 4 CTEs but never carried forward into the main chain — added to the select list.
4. `[Adj Create Operator]` / `[Adjusted Update Operator]` referenced a non-existent column
   `op1.[Final Operator]` / `op2.[Final Operator]` (compile error — `operator` table has no such
   column) — fixed to `CONCAT(op.first_name,' ',op.surname)`.
5. `[Branch]` (Qlik `ApplyMap('OperatorMapping',...)` with no default) was defaulting to NULL on a
   miss — Qlik's no-default ApplyMap returns the lookup key itself. Fixed with `ISNULL(...,
   [Final Operator])`.
6. `[Person ID]` / `[Person Name]` in the Adjustments CTE were sourced from `ClaimDetailsAtService
   .person_id` instead of `ClaimDetailGenAndHosp.person_id` — Qlik's duplicate-column resolution
   takes the first-loaded occurrence (`cd.person_id`). Fixed.
7. `[For Audit]`: `wob.claim_type <> 'Hospital' AND wob.[Provider Number] <> 'TRAVEL'` didn't
   account for NULLs on claims with no adjustment line (Qlik's `<>` against NULL evaluates true;
   SQL's is UNKNOWN and falls through). Fixed with `ISNULL(...,'')`.
8. `[Provider Number] LIKE '%SUNGLASS%'` was too loose — Qlik's `Wildmatch(x,'SUNGLASS')` with no
   `*`/`?` wildcards is an exact match. Fixed to `= 'SUNGLASS'`.
9. `NetWorkDays` (business-day count) was implemented as the standard *exclusive* formula in 3
   places and a cruder formula with no weekend adjustment at all in a 4th (`DaysTilPaid`) — Qlik's
   `NetWorkDays` is *inclusive* of both endpoints. Standardised all 4 occurrences to one inclusive
   formula (`... + 1`), using deterministic `DATEDIFF(...,'1900-01-01',...) % 7` weekday arithmetic
   (not `DATENAME(WEEKDAY,...)`, which is `@@LANGUAGE`-dependent) to match the `[Week End]` style.
10. `[Claim ID/Line ID String]` and every `first_name + ' ' + surname` operator-name expression used
    SQL `+`, which yields NULL if either side is NULL — Qlik's `&` treats NULL as empty string.
    Fixed to `CONCAT(...)` throughout.
11. `[Till Location]`: the `claim`→`till` lookup was missing the `create_datetime > @vStartDate`
    filter (present in the Qlik `TillMap` source), and was missing the `till`→`grouping` hop
    entirely — Qlik's `TillNameMap` returns `grouping.description`, not `till.description`. Fixed.
12. `OUTER APPLY ... TOP 1` (ClaimAttachment, Person Name lookups) had no `ORDER BY`, making the
    picked row non-deterministic on ties. Added `ORDER BY` for reproducibility.

**Third-pass review findings (against production-unqualified `dbo.` table names) — all fixed:**
13. `[Claim Channel]` (Qlik lines 186-187, an outer wrapping LOAD around the main `claim_status`
    load) was missing entirely — added, with a matching NULL placeholder in `ProviderClaimStatus`
    to keep the `UNION ALL` column-for-column aligned.
14. Bare `status_date` / `create_operator` fields from the Qlik Concatenate LOAD (lines 241-242)
    were missing from both union sides — added (NULL on the main-load side, real values on the
    provider side, matching Qlik Concatenate semantics of "missing field on one branch = NULL").
15. Three `ApplyMap('OperatorMap', <key>)` calls with no default argument (Qlik lines 327-329,
    feeding `[Final Operator]` / `AssessedOperatorCheck` / `VerifiedOperatorCheck`) were defaulting
    to NULL on a miss via `ISNULL(CONCAT(...), <key>)` — but `CONCAT(NULL,' ',NULL)` returns a
    single space `' '` in T-SQL, not NULL, so the `ISNULL` fallback never fired. Fixed to test
    `op_x.oper_name IS NULL` directly rather than relying on `CONCAT`'s output.
16. Same `CONCAT`-returns-space trap fixed for `[Adj Create Operator]` / `[Adjusted Update Operator]`
    (Qlik lines 492, 513 — `ApplyMap('OperatorMap', key, key)` with the key as explicit default).
17. `[Branch]` lookup join (line ~749) was still using `first_name + ' ' + surname` after a prior
    pass claimed to convert all such concatenations to `CONCAT` — missed occurrence, fixed.
18. `[Operator Branch]` join risked a runtime type-conversion error: `[Branch]` can hold either a
    numeric `branch_group_id` (as text) or, on an ApplyMap miss, an operator's name string: joining
    `grouping.group_id` directly against it could force SQL Server to attempt (and fail) an
    implicit string→numeric conversion. Fixed by casting `group_id` to string instead.
19. `[Claim Operator]`'s inner condition (Qlik lines 204-211 main load, 245-246 provider load) had
    used the "intended"/corrected `LEN(update_operator) > 0` test, inconsistent with the
    deliberately-kept-as-a-bug `len(update_operator>0)` always-true replication used for
    `[Final Operator]` (Qlik line 327, see [Deliberate Qlik-bug replications](#deliberate-qlik-bug-replications-principle-1--confirmed-with-user-not-silently-fixed)
    above). Same source bug, both occurrences now replicated identically as always-true, per
    explicit user confirmation.

**Regression introduced and then reverted within the third pass:** an attempt to make the
`VerifiedClaims` join "NULL-safe" on `[Verified Status Date]` (added an `OR (...IS NULL AND
...IS NULL)` branch) was based on a false premise — Qlik's `Left Join` does **not** treat
NULL=NULL as a match; it behaves like SQL's plain `=`. The added branch caused the join to
over-match (effectively allowing every non-Verified `Claims` row to match). Reverted to the
original plain equality, which was correct all along.

**Known limitations documented, not fixed (low risk, flagged for awareness):**
- `VerifiedClaims`/`AssessedClaims` → `dbo.operator` lookups test `op_x.oper_name IS NULL` as the
  "join missed" signal. This assumes `operator.oper_name` is `NOT NULL` in the schema (not yet
  confirmed against `INFORMATION_SCHEMA.COLUMNS`). If it can be NULL, the miss-test is still safe
  in practice (a NULL join key can never match), but worth confirming.
- `[Branch]` join on `CONCAT(first_name,' ',surname) = [Final Operator]` will pick an arbitrary
  matching row if two operators share the same full name (Qlik's `ApplyMap` returns the first
  match only); unlike the ClaimAttachment/Person lookups, this isn't wrapped in a deterministic
  `TOP 1 ... ORDER BY`. Low practical risk, not fixed.
- `ISNUMERIC()` (used for the `isnum()`/`'Web/Mobile Claim'` translation and Paid-operator
  numeric checks) is looser than Qlik's `isnum()` — it also accepts strings like `'$'`, `','`,
  `'1e5'` that Qlik would reject. Given operator codes are fixed-width `CHAR` values, practical
  risk is low; `TRY_CAST(x AS FLOAT) IS NOT NULL` would be a closer match if ever needed.

**Fourth-pass review findings — 2 fixed, everything else confirmed correct (full stage-by-stage
re-audit, including re-verifying all previously-fixed items were not undone):**
20. `TillMap` subquery (`ClaimStatusMain`, feeding `[Till Location]`) was missing `DISTINCT` —
    the Qlik source is explicit (`LOAD distinct`, line 154), and the sibling `MembershipIDMap`
    subquery already had it. Fixed to `SELECT DISTINCT claim_id, till_id`.
21. `BucketTypeMap` subquery (`GenHospBucket`, feeding `[Gen/Hosp Bucket Type]`) had no dedup at
    all. Qlik Mapping tables (as opposed to plain LOADs) are implicitly one-value-per-key even
    without an explicit `distinct` — `ApplyMap` can never return more than one value. Fixed with
    `GROUP BY claim_id` + `MIN(claim_type_flag)` (stronger guarantee than plain `DISTINCT`, which
    would still fan out if `claim_type_flag` varies per `claim_id`).

All 3 prior passes' fixes reconfirmed intact: the reverted Verified-join regression is still a
plain `=` (not reintroduced), `[Branch]` is still `VARCHAR(81)`, `[Claim Channel]` present on both
UNION ALL sides, all 3 no-default `ApplyMap` fixes still test `oper_name IS NULL`, both
deliberately-kept Qlik bugs (`isnum`/`Web/Mobile Claim`, `len(x>0)` always-true) still consistent
across all occurrences. UNION ALL re-counted at 28 columns per side, still aligned.

**Fifth-pass review findings — 2 fixed, 1 confirmed as a deliberate deviation (user decision):**
22. `[ClaimChannel]` / `[Claim Channel]` used `ISNULL(cbc.category, 'Top Up Claims (System
    Generated)')` in 3 places. `ISNULL`'s return type/width follows its **first** argument — if
    `ClaimsByChannel.category` is narrower than the 32-char default literal, the default would be
    silently truncated on every miss (same failure class as the `[Branch]` fix in pass 3). Fixed to
    `COALESCE(...)`, which resolves to the widest/highest-precedence type across all arguments and
    is immune to this truncation class.
23. `[Operator Branch]` had the identical `ISNULL(g.description, 'No Assigned Branch')` truncation
    risk (18-char default literal). Fixed to `COALESCE(...)`.

**Deliberate deviation from Qlik (confirmed with user — Principle 1 exception, not an oversight):**
`[MonthYear]` uses `FORMAT(status_date, 'MMM yyyy')`, producing e.g. `'Jan 2026'`. The Qlik script
sets `SET MonthNames='Jan.;Feb.;Mar.;...'` (line 15, period-suffixed abbreviations, `May` being the
sole exception), so Qlik's `monthname()` actually emits `'Jan. 2026'`, `'Sep. 2026'`, etc. — an
11-of-12-months string mismatch against the SQL's unpunctuated output. **User confirmed: keep the
SQL as-is (no periods)** rather than reproducing Qlik's punctuation. If `[MonthYear]` is ever used
to join or filter against a Qlik-sourced string value downstream, this mismatch would need
revisiting.

All fourth-pass fixes (`TillMap`/`BucketTypeMap` dedup) reconfirmed intact. Deep-dive checks on
aggregate/subquery duplicate handling, CTE field-threading across all 17 stages, the final
`[For Audit]` CASE (re-derived from scratch), `@vStartDate`/`@vToday`/`GETDATE()` scope correctness,
and the `Adjustments` join chain's exact JOIN types (LEFT/LEFT/INNER/LEFT matching Qlik 521-525)
all confirmed correct with no further findings.

**Sixth-pass review findings — 2 fixed:**
24. `[Till Location]` still used `ISNULL(till_g.description, 'No Till')` — the exact truncation
    class fixed for `[ClaimChannel]`/`[Operator Branch]` in pass 5 (same `grouping.description`
    column), missed on this occurrence. More likely to bite in practice than the pass-5 instances,
    since a Till miss is the common case, not the exception. Fixed to `COALESCE(...)`.
25. `[HO/Care Centre]`: Qlik line 588 has a trailing-space typo, `'Jaide Vanneste '`, in the
    `match([Final Operator], ...)` list. Qlik's `match()` is an exact comparison, so — since
    `[Final Operator]` (`CONCAT(first_name,' ',surname)`) never carries a trailing space — **that
    entry never matches in the real Qlik output**; Jaide Vanneste is always classified
    `'Care Centres'`. T-SQL's default (non-binary) string comparison ignores trailing spaces
    (ANSI blank-padding), so a plain `IN (...)` would make this entry match and silently flip her
    to `'Head Office'` — a divergence invisible to a text diff of the two literal lists, since the
    strings are byte-identical; only the comparison *semantics* differ. **User confirmed: replicate
    Qlik's actual (buggy) output**, not the presumed intent. Fixed by adding
    `COLLATE Latin1_General_BIN2` to the `[Final Operator] IN (...)` comparison, which makes
    trailing spaces (and case) significant, matching Qlik's exact-match behaviour for this list.

Confirmed correct, not changed: `ISNULL(bt.claim_type_flag,'Missing')` (`GenHospBucket`,
`[Gen/Hosp Bucket Type]`) has the same latent truncation exposure (`claim_type_flag` is `CHAR(1)`-ish,
`'Missing'` would truncate) but the result is only ever tested `= 'H'`, and no possible truncated
value equals `'H'` — outcome-neutral, left as `ISNULL` to keep the diff focused on things that
actually change behaviour.

Exhaustive re-inventory of every Qlik LOAD-block field alias (all ~180 occurrences) against the
SQL confirmed no dropped fields anywhere. Collation/case-sensitivity, the `SUBSTRING(x,1,
CHARINDEX('-',x)-1)` operator-code-split pattern (6 occurrences, including the leading-hyphen edge
case), statement/batch boundaries, `DECIMAL(9,0)` precision through every CAST/CONCAT, and the
Total-table exclusion boundary (no orphaned fragments from the excluded Qlik lines 647-771) all
confirmed clean.

**Seventh-pass review findings — 1 fixed (CRITICAL, hard runtime failure, not just wrong data):**
26. `CurrentProduct`/`CurrentAgent` exposed `membership_id` at its native `DECIMAL(9,0)` type from
    `MemberCover`/`MemberAgent`, then joined it against `dtp.[Membership ID]`, which is `VARCHAR(20)`
    and commonly holds the literal sentinel `'no member'`. SQL Server's numeric type precedence
    would coerce the VARCHAR side to numeric on join — raising a hard
    `Msg 8114: Error converting data type varchar to numeric` the moment it hit a `'no member'` row,
    **aborting the entire query**. This is not a rare edge case: `c_mem`'s `create_datetime` filter
    and the outer `status_date` filter don't align, so any claim created before the 13-month window
    but status-updated inside it produces `'no member'` — a large, guaranteed population on real
    data. Same defect class already guarded against for `[Branch]`/`grouping.group_id` (pass 3,
    finding #18) but missed here. Fixed by casting `membership_id` to `VARCHAR(20)` in both CTEs,
    matching the existing `[Branch]` pattern.

Confirmed correct, not changed (re-verified from pass 6): `ISNULL(bt.claim_type_flag,'Missing')`
remains outcome-neutral, left as-is. All 25 previously-documented fixes spot-checked and intact,
including the `COLLATE Latin1_General_BIN2` fix (#25) and all three no-default `ApplyMap` sites.
Five of six focus areas (inline-SQL column-list fidelity across all 5 `claim_status` queries,
`@vStartDate` scope across all ~15 occurrences, nested `if()`/`and` precedence re-parsed from raw
text, `//` comment/dead-code boundaries, column-shadowing across all 17 wildcard stages) came back
clean. The finding came from the type-consistency angle — the same angle that has now produced
real, high-severity findings twice (`[Branch]` in pass 3, this one in pass 7).

**Note:** as of this pass the query still had never been executed against a real database. This
finding — a guaranteed-to-fire hard error, not a subtle logic bug — is exactly the kind of defect
that a single test execution would surface immediately. Static review is not a substitute for
actually running the query.

**Eighth-pass review findings — 2 fixed (both LOW severity; priority sweep of the type-mismatch
pattern that produced passes 3 and 7's high-severity findings came back completely clean — all
~30 join/comparison predicates in the file individually typed and verified, no third
`[Membership ID]`-class asymmetry anywhere):**
27. `[Attachment Subject]` still used `ISNULL(ca.letter_subject, 'No Attachment')` — the same
    truncation class fixed for `[ClaimChannel]`/`[Operator Branch]`/`[Till Location]` in passes
    5-6, missed on this occurrence. A miss (no correspondence row) is the common case. Fixed to
    `COALESCE(...)`.
28. `[MonthYear]`'s `FORMAT(status_date,'MMM yyyy')` infers as `NVARCHAR(4000)` — not a
    correctness issue today (the `UNION ALL` with `ProviderClaimStatus`'s `VARCHAR(8)` placeholder
    resolves to the wider type without truncation either way), but relevant given Hippo will later
    materialise this query into a table (see Output scope / Ownership above): a naive schema
    inference off this SELECT would hand Hippo an 8000-byte column for an 8-character value.
    Wrapped in `CAST(... AS VARCHAR(8))` for a clean inferred schema; `'MMM yyyy'` output is never
    longer than 8 characters.

Full type audit (join predicates, CHAR blank-padding behaviour, UNION ALL type/width alignment
across all 28 column pairs, DATE-vs-DATETIME consistency for every logically-shared field) found
no further issues. All 26 previously-documented fixes reconfirmed intact, including both
type-mismatch fixes (`[Branch]`/`group_id` cast direction, `[Membership ID]` CurrentProduct/
CurrentAgent casts) and all four deliberate deviations.

**Ninth-pass review — zero new findings.** Checked five angles deliberately different in kind from
passes 1–8: (1) full end-to-end CTE chain trace (26 CTEs, each defined once, no dead/undefined
references), (2) fact-check of every inline SQL comment's Qlik line-number/behaviour claims against
the raw source (all accurate), (3) manual business-scenario tracing for `[Final Operator]`,
`MaxStatus`, `[Bucket Type]`, `[Held Days]` across Verified/Cancelled/untouched/provider-only claim
scenarios (all produced business-reasonable results), (4) `@vStartDate` re-derivation against 3
concrete "today" dates including a leap-year edge case (SQL matches Qlik exactly), plus a
16,000-date-pair brute-force check of the `NetWorkDays` formula (0 mismatches), (5) a sweep for any
non-deterministic construct that could make Hippo get different results materialising this at two
different times (none found — the two `OUTER APPLY TOP 1` sites are both deterministic by
construction, not by luck).

(Interim note from pass 9, superseded by the summary at the end of this section: at that point the
count stood at 43 fixes across 9 passes, trend 19→7→8→2→2→2→1→2→0, and the conclusion was that
static review had reached diminishing returns and the remaining risk required actual execution to
verify. Passes 10 and 11 subsequently confirmed that conclusion — see below.)

**Tenth-pass review findings — 1 raised, assessed, and deliberately NOT fixed (user decision):**
29. `[MonthYear]`'s `FORMAT(status_date,'MMM yyyy')` has no `culture` argument, so its output
    technically follows the executing session's language setting (e.g. would differ under a
    non-English session). Same class of session-dependence the project engineered out for
    `[Week End]` (pass 1, fix #9). **User reviewed and explicitly declined this fix** — the
    execution environment is known/controlled to be English, so pinning a culture argument was
    judged unnecessary defensive coding for a condition that won't occur in practice. Left as
    `FORMAT(status_date,'MMM yyyy')`, no culture argument.

Also newly verified this pass (all clean, no changes): every field referenced in
`qlik_measures_to_replicate.md` (12 distinct fields — `MaxStatus`, `[Bucket Type]`,
`[Bucket Claims]`, `claim_type`, `[Days to Verify Claim]`, `Status`, `[Final Operator]`,
`[Claim Operator]`, `[Claim Line]`, `update_datetime`, `[Claim ID]`, `[Date]`) is produced by
`select_Claims.sql` with an exact-matching name and correct value domain — this cross-file check
had never been run before pass 10. All five slash-bearing bracketed identifiers
(`[Gen/Hosp Bucket Type]`, `[Claim ID/Line ID String]`, `[HO/Care Centre]`, etc.) are correctly
bracketed at every occurrence, not just their definition. The five dead mapping tables
(`ItemMap`/`PersonMap`/`ProviderMap`/`BucketMap`/`DepartmentMap`) re-confirmed dead by searching
for their *names* anywhere in the project (not just `ApplyMap` calls) — no hits beyond their own
definitions. `[Person Name]`'s `dbo.person` `OUTER APPLY` (replacing Qlik's QVD-sourced
`PersonNameMap`) confirmed correct and consistent with the project's already-accepted
QVD→live-table substitution pattern used for all six QVD sources.

**No TODO/FIXME markers, no internal-only context** — vendor-handoff hygiene otherwise clean (the
`[MonthYear]` session-setting dependence noted above was reviewed and deliberately left as-is).

**Eleventh-pass review — zero new SQL logic findings.** Checked four angles novel relative to
passes 1–10: (1) re-derived the `AgeInBucketCohorts`/`HeldAgeCohorts` band boundaries
character-by-character from the raw Qlik inline tables (identical, no off-by-one, including both
source labelling oddities); confirmed `BucketAgeCohort`/`HeldAgeCohort` are terminal output columns
with no downstream Qlik or measures-file consumer, so the SQL's direct-CASE translation (vs.
threading Qlik's `agemin`/`agemax` bridge keys) is behaviourally equivalent; (2) re-verified all
Qlik line-number citations across every inline SQL comment are still accurate; (3) re-confirmed
`[Received Year]`'s "copy-paste artifact" framing — the field is consumed nowhere downstream in
Qlik or in `qlik_measures_to_replicate.md`, so it's a pure terminal output column and the existing
"replicate faithfully, it's inert" conclusion stands; (4) reviewed this document (DESIGN.md) itself
for internal consistency as a standalone artifact — found several drifted/contradictory sections
(now corrected: the stale "not yet started" status line, the "not yet generated" file-tree
annotation, the 15-vs-17-stage and 20-vs-21-table count mismatches, the buried/stale pass-9
conclusion, and inconsistent "BRONZE" terminology). None of this pass's findings touched
`select_Claims.sql` — only this file.

**Summary across all 11 passes:** 44 fixes applied, 1 additional finding raised and explicitly
declined by the user (pass 10, `[MonthYear]` culture pinning). Finding counts by pass:
19→7→8→2→2→2→1→2→0→1(declined)→0. Static review of `select_Claims.sql` has reached a stable fixed
point — three consecutive passes (9, 10, 11) found no new SQL logic defects. **The remaining risk
is entirely execution-shaped and not findable by further reading** — see the "Still open" list at
the end of this document. Recommendation: move to execution-based validation (a `SET PARSEONLY ON`
or `SET NOEXEC ON` compile check would resolve the ~30 unconfirmed BRONZE column names in one step;
an actual run against the live database is needed for everything else on that list).

---

## Objects NOT Built

| Object | Reason |
|---|---|
| `Total` (final summary table, Qlik lines 647–771) | Still not a deliverable — `select_Claims.sql` remains the only pure-SELECT output. A validation-only script, `select_Total_QUICKCHECK.sql`, was built 2026-09-08 to sanity-check `Total`'s logic against the dashboard's left-side Operator summary pivot (see "Total table validation" below) — this is diagnostic, not a scope change. `Total` is fully derived from `Claims` (5x Concatenate + 4x self Left Join, no new BRONZE sources beyond what `Claims` already reads) — if built as a real deliverable later, it can be added independently by reading from `SILVER.dbo.Claims` without re-touching `Claims` or its source mapping. |

---

## Files to Generate

```
sql_db/DWH_/23_claims_processing_summary/
├── DESIGN.md                          ← this file
├── claims_processing.md               ← source Qlik script
├── qlik_measures_to_replicate.md      ← Qlik set-analysis measures (reference only)
└── select_Claims.sql                  ← pure SELECT, no table/SP — drafted, not yet executed
```

---

## Refresh Strategy

Not applicable — no table or stored procedure is being built in this project. `select_Claims.sql`
is a standalone query the caller runs directly against the production database (see the file's
header comment — table references are unqualified `dbo.xxx`, not `BRONZE.dbo.xxx`; "BRONZE" here
refers to the architectural layer, not a literal database name to prefix — see line 7).

---

## Known Data Behaviour Notes

- **`ManualClaimFlag` join is by `[Claim ID]` only, not by claim line.** The Qlik Left Join at
  lines 529-536 auto-joins on same-named fields; the Manual Claim QVD load produces
  `[Claim Line ID]`, which does NOT match the Adjustments join's `[Claim Line]` (different field
  name) — so Qlik only matches on `[Claim ID]`. If a claim has multiple `claim_line_id` rows in
  `Paragon_Claim_GeneralItem.qvd` / `claim_generalitem`, this produces one output row per matching
  line (row multiplication), same as the original Qlik behaviour — not a translation bug, a
  faithful replication of how Qlik's LOAD would behave.
- `fee` is `MONEY` in `ClaimDetailGenAndHosp` — the Qlik `fee > '0.00'` string comparison relies on
  Qlik's implicit type coercion and is equivalent to a numeric `fee > 0.00` in SQL. No behaviour
  difference.

## Runtime Validation — `select_Claims_QUICKCHECK.sql` vs Qlik Dashboard

A trimmed validation script, `select_Claims_QUICKCHECK.sql`, was built to sanity-check
`select_Claims.sql`'s core logic (`MaxStatus`/`[Bucket Type]`/`[Final Operator]`/`[Claim Operator]`/
`claim_type`/`[Days to Verify Claim]`) against the live Qlik "Summary" dashboard, without waiting for
the full 21-table/17-stage query (which did not complete in 40+ minutes). It computes the 12 number
cards + 3 Date cards from the dashboard as scalar subqueries over a shared CTE chain. **This script
is validation-only — not the deliverable, not handed to Hippo.**

**Result (two independent runs, 2026-09-07 and 2026-09-08, ~1 day apart):** 7 of 15 values match
exactly and are stable across both runs; 8 are consistently low, with near-identical percentage gaps
both times — indicating a systematic cause, not a one-off data or timing issue.

**Run 1 (2026-09-07):**

| Metric | Dashboard | QUICKCHECK | Match |
|---|---|---|---|
| Total Claims in the Bucket | 770 | 770 | ✅ |
| Medical Claims in the Bucket | 118 | 118 | ✅ |
| Hospital Claims in the Bucket | 153 | 153 | ✅ |
| General Claims in the Bucket | 499 | 499 | ✅ |
| Date (Medical) | 26/8/2026 | 2026-08-26 | ✅ |
| Date (Hospital) | 4/9/2026 | 2026-09-04 | ✅ |
| Date (General) | 1/9/2026 | 2026-09-01 | ✅ |
| Avg Days Til Verified (Medical) | 20 | 3 | ❌ -85% |
| Avg Days Til Verified (Hospital) | 7 | 4 | ❌ -43% |
| Avg Days Til Verified (General) | 5 | 2 | ❌ -60% |
| Claims Added to Bucket - Medical | 10,230 | 6,391 | ❌ -37.5% |
| Claims Added to Bucket - Hospital | 90,340 | 60,124 | ❌ -33.5% |
| General Claims Logged | 201,638 | 144,759 | ❌ -28.2% |
| Medical Claims Processed | 4,262 | 4,252 | ❌ -0.2% |
| General Claims Processed | 166,180 | 120,657 | ❌ -27.4% |
| Processed excl. Electronic | 59,677 | 58,851 | ❌ -1.4% |

**Run 2 (2026-09-08):**

| Metric | Dashboard | QUICKCHECK | Match |
|---|---|---|---|
| Medical Claims in the Bucket | 86 | 86 | ✅ |
| Hospital Claims in the Bucket | 162 | 162 | ✅ |
| General Claims in the Bucket | 430 | 430 | ✅ |
| Date (Medical) | 27/8/2026 | 2026-08-27 | ✅ |
| Date (Hospital) | 7/9/2026 | 2026-09-07 | ✅ |
| Date (General) | 3/9/2026 | 2026-09-03 | ✅ |
| Avg Days Til Verified (Medical) | 20 (unchanged) | 3 | ❌ -85% |
| Avg Days Til Verified (Hospital) | 7 (unchanged) | 4 | ❌ -43% |
| Avg Days Til Verified (General) | 5 (unchanged) | 2 | ❌ -60% |
| Claims Added to Bucket - Medical | 10,237 | 6,398 | ❌ -37.5% |
| Claims Added to Bucket - Hospital | 90,537 | 60,321 | ❌ -33.4% |
| General Claims Logged | 202,106 | 145,227 | ❌ -28.1% |
| Medical Claims Processed | 4,271 | 4,261 | ❌ -0.2% |
| General Claims Processed | 166,768 | 121,246 | ❌ -27.3% |
| Processed excl. Electronic | 59,848 | 59,022 | ❌ -1.4% |

**Grouping of the 8 mismatches, by suspected cause:**

1. **`[Bucket Type]`-dependent counts (4): Claims Added to Bucket - Medical/Hospital, General
   Claims Logged, General Claims Processed.** All rely on the same `GenHospBucket`/`ProviderBucket`
   join chain (`dbo.claim_alloc` / `dbo.provider_claim_alloc`). Confirmed via direct queries against
   BRONZE:
   - `claim_alloc` (205,091 rows in the 13-month window) and `provider_claim_alloc` (6,392 rows) are
     each far smaller than `claim_status` (34.7M rows total; ~1.18M distinct claims in the window) —
     `claim_alloc`'s monthly row counts are stable (13k–17k/month, no gaps), so this is not a data
     ingestion outage.
   - Of the ~767k `Status = 'Received and Logged'` rows in the window, 73% (561,101) have no matching
     row in `claim_alloc`/`provider_claim_alloc` **at all**, at any point in time (not just outside
     the 13-month window) — confirmed these claims are absent from `claim_alloc` unconditionally.
   - The join predicates, `create_datetime > @vStartDate` filters, and `@vStartDate` formula itself
     were all re-verified character-by-character against Qlik lines 385-421 — translation is exact,
     no divergence found.
   - The Qlik measure expressions themselves (`Count({<Status = {'Received and Logged'}, [Bucket
     Type] = {'Hospital'}>}distinct [Claim ID])` etc.) were confirmed directly from the Qlik app
     (Edit measure) — match `qlik_measures_to_replicate.md` and the SQL translation exactly, no
     hidden dimension limits or extra modifiers.
   - **Conclusion: cause not yet found.** Given the SQL is a verified-faithful translation of the
     `.md` script (see full line-by-line diff below), and the Qlik measure expressions are confirmed
     exact, the remaining hypothesis is that the Qlik app's live data differs from what this query
     sees at the SQL Server level (e.g. a reload/refresh timing gap, or a data-model association Qlik
     resolves differently than an explicit SQL JOIN) — **not yet confirmed**, requires drilling into
     a specific Claim ID from the Qlik app (attempted, not currently possible for the user) or
     confirming the Qlik app's last full reload timestamp/script against this `.md` file.
2. **Avg Days Til Verified — Medical/Hospital/General (3).** Largest percentage gaps (-43% to
   -85%), and **unchanged across 3 separate dashboard views spanning 2 days** (20/7/5 every time)
   despite the other 4 `[Bucket Type]`-dependent numbers moving with data growth day to day. This
   points to a different root cause than group 1 — most likely these dashboard cards are not
   recomputed live (cached/scheduled value, or bound to a different/static field) rather than a
   SQL translation defect. Deprioritised pending confirmation from whoever manages the Qlik app.
3. **Medical Claims Processed, Processed excl. Electronic (2).** Gaps under 1.5% (essentially
   matching) — the `claim_type` (via `ClaimDetailGenAndHosp`) and `[Final Operator]`/`[Claim
   Operator]` exclusion logic these depend on is confirmed sound; residual gap is most likely just
   the dashboard-refresh-vs-query-runtime timing difference, not a logic issue. Not prioritised.

**`claims_processing.md` re-verified against a pasted copy of the live Qlik script (2026-09-08):**
user supplied the Qlik script directly from the app; a byte-level `diff -B -w` (ignoring
whitespace-only differences) against `claims_processing.md` found **zero substantive differences** —
confirms the `.md` file is not stale and is a faithful copy of the script through `Rename Table
AdditionalLogic to Total;` (line 771). Separately, the user also has an `Exit Script;` statement
followed by 4 further `outer join`-based `Total` table variants in their live app copy — these
appear **after** the `Total:` table definition already captured in `.md`, so per Qlik's `Exit
Script;` semantics (execution stops immediately, nothing after it runs) they are unreachable dead
code and do not affect anything documented in this file, including the in-scope `Claims` logic.

**Next steps for the group-1 gap:** confirm with whoever administers the Qlik app (a) the timestamp
of its last full script reload and (b) whether the reloaded script matches `claims_processing.md`
exactly. If confirmed matching and recently reloaded, the next diagnostic step is drilling a specific
Claim ID from a "Claims Added to Bucket" dashboard card (blocked — not currently possible for the
user via the Qlik UI) to directly compare its `[Bucket Type]` resolution between Qlik and SQL Server.

### Follow-up (2026-09-08): window-width experiment confirms group-1's root cause

**Quick-reference summary of all 15 dashboard numbers, 13-month window vs wide window:**

| # | Metric | 13-month window | Wide window (2025-01-01) | Status |
|---|---|---|---|---|
| 1 | Total Claims in the Bucket | ✅ Match | — | ✅ |
| 2 | Medical Claims in the Bucket | ✅ Match | — | ✅ |
| 3 | Hospital Claims in the Bucket | ✅ Match | — | ✅ |
| 4 | General Claims in the Bucket | ✅ Match | — | ✅ |
| 5 | Date (Medical) | ✅ Match | — | ✅ |
| 6 | Date (Hospital) | ✅ Match | — | ✅ |
| 7 | Date (General) | ✅ Match | — | ✅ |
| 8 | Claims Added to Bucket - Medical | ❌ -37.5% | ✅ +0.9% | 🔧 fixed by wider window |
| 9 | Claims Added to Bucket - Hospital | ❌ -33.4% | ✅ +0.5% | 🔧 fixed by wider window |
| 10 | General Claims Logged | ❌ -28.1% | ✅ +0.7% | 🔧 fixed by wider window |
| 11 | General Claims Processed | ❌ -27.3% | ✅ +0.7% | 🔧 fixed by wider window |
| 12 | Medical Claims Processed | ✅ -0.2% (close) | ❌ +55.8% | ⚠️ wider window makes it worse |
| 13 | Processed excl. Electronic | ✅ -1.4% (close) | ❌ +47.7% | ⚠️ wider window makes it worse |
| 14 | Avg Days Til Verified (Medical) | ❌ -85% | ❌ -85% (unchanged) | ❓ cause unknown, window-independent |
| 15 | Avg Days Til Verified (Hospital) | ❌ -43% | ❌ -43% (unchanged) | ❓ cause unknown, window-independent |
| 16 | Avg Days Til Verified (General) | ❌ -60% | ❌ ~-60% (unchanged) | ❓ cause unknown, window-independent |

Legend: ✅ matches — 🔧 fixable by widening the window — ⚠️ widening the window breaks an
already-matching number — ❓ neither window works, root cause not yet found.

The Qlik dashboard's `MonthYear` filter listbox (Summary sheet) shows selectable months back to
**Jan 2025** — about 7 months earlier than `@vStartDate`'s 13-month rolling window computes for
"today" (2026-09-08 → Aug 2025). This raised a new hypothesis: the SQL's 13-month window is
narrower than whatever window the live Qlik app is actually using, which would under-count
anything sensitive to how many claims are in scope.

**Test:** a one-off diagnostic run with `@vStartDate` hardcoded to `2025-01-01` instead of the
dynamic 13-month formula (tested in-place in `select_Claims_QUICKCHECK.sql` — that file now carries
both formulas, 13-month active and `2025-01-01` commented out beside it, so this can be re-tested
without a separate file), was run and compared against the same-day dashboard screenshot (2026-09-08):

| Metric | Dashboard | 13-month window | Wide window (2025-01-01) | Result |
|---|---|---|---|---|
| Claims Added to Bucket - Medical | 10,237 | 6,398 (-37.5%) | 10,327 (+0.9%) | ✅ confirmed |
| Claims Added to Bucket - Hospital | 90,537 | 60,321 (-33.4%) | 90,983 (+0.5%) | ✅ confirmed |
| General Claims Logged | 202,106 | 145,227 (-28.1%) | 203,562 (+0.7%) | ✅ confirmed |
| General Claims Processed | 166,768 | 121,246 (-27.3%) | 167,954 (+0.7%) | ✅ confirmed |
| Medical Claims Processed | 4,271 | 4,261 (-0.2%) | 6,655 (+55.8%) | ❌ got worse |
| Processed excl. Electronic | 59,848 | 59,022 (-1.4%) | 88,393 (+47.7%) | ❌ got worse |
| Avg Days Til Verified (all 3) | 20/7/5 | 3/4/2 | 3/4/3 | ⚪ unaffected |
| Bucket-count + Date cards (7) | — | exact match | exact match | ⚪ unaffected |

**Conclusion:** window width is the confirmed root cause for group 1 (the 4 `[Bucket Type]`-driven
counts) — widening `@vStartDate` closes each of those 4 gaps to under 1%. But the same widening
makes the 2 previously-near-matching numbers (Medical Claims Processed, Processed excl. Electronic)
**worse** — both roughly double their gap from the dashboard. This means **a single global
`@vStartDate` cannot satisfy both groups simultaneously**: the `[Bucket Type]` counts need a wider
window (claims allocated to a bucket long ago still need to be countable), while the
`Status`-filtered "Processed" counts are naturally self-limiting (a claim sitting in an
in-progress status like `Verified`/`Assessed but not Verified` is very unlikely to be old — the
13-month window already captures effectively all of them) and a wider window mainly adds
*stale/already-resolved* claims that shouldn't count, inflating the number instead of correcting it.

The Avg Days Til Verified group (3) is confirmed **unrelated to window width** — identical results
under both windows, reinforcing the earlier hypothesis that those 3 dashboard cards are not driven
by a live recompute over the same data window at all (cached/scheduled value, or a different
binding) rather than a SQL translation gap.

**Not yet resolved:** why the `[Bucket Type]`-driven counts need a wider window than 13 months in
the first place — i.e. what the live Qlik app's *actual* effective `vStartDate` is, and whether
`claims_processing.md`'s `Let vStartDate = Date(MonthStart(AddYears(today(), -1), -1));` formula
(13 months) is still what the live app runs, or has been changed/overridden since this `.md` was
captured. This finding is diagnostic only — no change has been made to `select_Claims.sql` (the
actual deliverable) or its `@vStartDate` formula, pending confirmation of what window Qlik is
really using.

### Follow-up (2026-09-09): `ClaimTypeOnly` missing an `INNER JOIN`, found on re-check

A full line-by-line re-comparison of `select_Claims_QUICKCHECK.sql` against `claims_processing.md`
found `ClaimTypeOnly` (feeds `claim_type`, needed by 6 of the 12 target numbers) was missing the
`INNER JOIN dbo.ClaimDetailsAtService ON claim_id AND claim_line_id` that `select_Claims.sql`'s
`Adjustments` CTE has (matching Qlik line 524) — `ClaimTypeOnly` queried `ClaimDetailGenAndHosp`
directly, admitting rows Qlik's actual join would exclude. This script had never had this specific
join checked against `select_Claims.sql` in prior passes; the omission was found only when asked to
re-compare the whole file line-by-line rather than spot-check known problem areas. Fixed by adding
the `INNER JOIN`. Not yet re-run against the dashboard to see whether this changes the `claim_type`
-dependent numbers (Avg Days Til Verified x3, Medical/General Claims Processed, Processed excl.
Electronic) — the "Avg Days Til Verified unchanged across window sizes" mystery (group 2 above) is
**not** expected to be explained by this fix, since a narrower/wider claim_type population wouldn't
make a dashboard number freeze at a fixed value across days; it's flagged here because it's a real,
independently-found translation gap worth fixing regardless of whether it explains that mystery.

A second issue found on the same pass: `ClaimsWithOperators` (feeds `ClaimsWithOperators3`) carries
a stray `_dummy` column (`CASE WHEN cu.[Membership ID] IS NULL THEN NULL ELSE 'x' END`) with no
Qlik equivalent and no downstream consumer anywhere in the file — dead code, harmless to the 12
numbers, not yet removed.

### Follow-up (2026-09-09): `[Final Operator]` ApplyMap-without-default bug, found on a second full line-by-line pass

A further full re-comparison (every CTE checked field-by-field against its Qlik counterpart, plus
all 4 implicit `Left Join` keys re-derived from scratch) found a real bug in `ClaimsWithOperators3`.
Qlik line 327 is `applymap('OperatorMap', if(len(update_operator>0), update_operator,
[ClaimOperator])))` — a **2-argument** ApplyMap call with no default value. In Qlik, an ApplyMap
call with no default returns `NULL` when the lookup value isn't found in the mapping table. The SQL
translation instead fell back to `co.[update_operator]` (the raw value) when `op_final.oper_name IS
NULL` (i.e. the operator wasn't found in `dbo.operator`) — silently substituting a value Qlik would
never produce. Fixed: the fallback branch was removed so `[Final Operator]` is `NULL` (via `CASE
WHEN ... THEN CONCAT(...) END` with no ELSE) whenever the operator lookup misses, matching Qlik's
no-default ApplyMap semantics exactly. This affects any of the 12 numbers that filter on
`[Final Operator]` (Medical/General Claims Processed use `[Final Operator] NOT IN (...)`), since an
incorrectly-populated non-NULL value could flip which side of the `NOT IN (...) OR IS NULL` filter a
row lands on. Not yet re-run against the dashboard.

The rest of this second pass — `ClaimStatusMain`, `ProviderClaimStatus`, `VerifiedClaims`/
`AssessedClaims` (confirmed correctly omitting `[Verified Operator]`/`[Assessed Operator]`, which
are unused by any of the 12 target numbers), all 4 implicit join keys (`ClaimsWithOperators`'s two
joins, `BringTogether`'s four joins, `Final`'s `ClaimTypeOnly` join), `MaxStatusProvider`/
`MaxStatusOther`, `GenHospBucket`/`ProviderBucket`, and the `[Days to Verify Claim]` NETWORKDAYS
formula — were re-checked line-by-line and found to match `claims_processing.md`. No further
discrepancies found.

### Third pass (2026-09-09): every ApplyMap call checked individually for arg count/default value

Because the `[Final Operator]` bug above was specifically an ApplyMap-default-value mistake missed
by two prior "logic-level" passes, a third pass went through every `ApplyMap`/`applymap` call in
`claims_processing.md` that's in scope for this file (i.e. not part of Till/Attachment/ClaimChannel/
Person/Product/Agent/Branch/Audit, which this file drops entirely) and explicitly counted arguments
and compared default values against the SQL, rather than checking whether the mapping "looked right":

- `ApplyMap('MembershipIDMap', claim_id, 'no member')` (lines 193/266/289/306, 3-arg) → SQL's
  `ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')` — default matches, confirmed on
  all three CTEs that carry `[Membership ID]` (`ClaimStatusMain`, `VerifiedClaims`, `AssessedClaims`).
- `applymap('ClaimStatusTypeMap', claim_status_type, 'MISSING')` (line 195, 3-arg) → SQL
  `ISNULL(cst.description, 'MISSING')` — matches.
- `applymap('ProviderClaimStatusTypeMap', provider_claim_status_type, 'Missing')` (line 239, 3-arg,
  **lowercase** `'Missing'`, for the `[Status]` field itself) vs. the *same* mapping re-called with
  **uppercase** `'MISSING'` at lines 245/247/248/249 for `[Claim Operator]`/`[Received Status Date]`/
  `[Paid Status Date]`/`[Verified Status Date]` — a genuine case inconsistency in the Qlik source
  itself (different default string depending on which field re-derives the status description).
  Checked the SQL: `ProviderClaimStatus` line 96 correctly uses `'Missing'` for `Status`, while lines
  98 and 105 independently use `'MISSING'` for `[Verified Status Date]`/`[Claim Operator]` — this was
  **already handled correctly**, not a bug.
- `applymap('OperatorMap', update_operator)` (line 327, **2-arg, no default** — the bug fixed above).
- `Applymap('BucketTypeMap', claim_id, 'Missing')` (line 388, 3-arg) → SQL's
  `ISNULL(bt.claim_type_flag, 'Missing')` — matches.
- All other `ApplyMap` calls in the file (`TillMap`/`TillNameMap`/`ClaimAttachment`/`ClaimChannelMap`/
  `PersonNameMap`/`OperatorMapping`/`GroupingMap`/`ItemMap`, and the Total-table-only
  `[AssessedOperatorCheck]`/`[VerifiedOperatorCheck]`/`[Adj Create Operator]`/
  `[Adjusted Update Operator]` at lines 328-329/492/513) feed fields this file deliberately drops per
  its header comment — confirmed out of scope, not silently missing.

No further ApplyMap-related discrepancies found. This pass also re-confirmed the `match()`/
`Wildmatch()` calls in scope (`match(Status,'Verified','Cancelled','Assessed but not Verified')` →
`Status IN (...)`; `match(claim_alloc_reason_id, 1)`/`match(..., 2)` → `= 1`/`= 2`) already matched.

### Fourth pass (2026-09-09): full field-by-field re-derivation of every implicit join key, plus a previously-unchecked `Left Join` block

After the `[Final Operator]` bug, trust in the file was low enough to warrant re-deriving every implicit
`Left Join` key from the raw Qlik field lists again, from scratch, rather than reusing the earlier
conclusion — plus an explicit search for any `Left Join (Claims)` block in `claims_processing.md` that
had not yet been individually checked against the SQL.

- **Found one previously-unnoted `Left Join (Claims)` block**: "Paid Claims for Online" (Qlik lines
  302-319, between the Assessed/Received join and `OperatorCheck:`). It computes `PaidStatus`,
  `[Paid Operator]`, `[PaidStatusDate]`, `[PaidCreateOperator]`, which feed only
  `[Online Claim Touched/Untouched]` (line 336) — not referenced by any of this file's 12 target
  numbers. Confirmed legitimately out of scope, not a silent omission — but it had never been
  individually named/checked in any prior pass, only implicitly assumed covered by the "Trimmed
  relative to select_Claims.sql" header comment.
- **Re-derived, from the raw Qlik field lists (not from memory), the join key for every `Left Join`
  this file depends on**: `ClaimsWithOperators`'s two joins (Verified Claims → `[Claim ID]` +
  `[Membership ID]` + `[Verified Status Date]`; Received/Assessed Claims → `[Claim ID]` +
  `[Membership ID]` only — re-confirmed neither collides with `[VerifiedStatusDate]`, a distinct
  field name from `[Verified Status Date]` with no space), `BringTogether`'s four joins
  (`MaxStatusProvider`/`MaxStatusOther`/`GenHospBucket`/`ProviderBucket`, all `[Claim ID]` alone), and
  `Final`'s `ClaimTypeOnly` join (`[Claim ID]` alone — re-confirmed `membership_id` in the Adjustments
  LOAD does not collide with `[Membership ID]` already in `Claims`, since Qlik field names are
  space/case-distinct). All matched the SQL exactly on this re-derivation.
- **Re-verified `[ClaimOperator]` (no space, line 335) is correctly absent from the SQL.** Traced
  Qlik's `OperatorCheck:` stacked-LOAD block (321-339) execution order explicitly: Qlik evaluates
  bottom-up (line 334's `Resident Claims` LOAD runs first, defining `[ClaimOperator]`; line 326's LOAD
  runs after, defining `[Final Operator]`), so `[ClaimOperator]` genuinely is available when
  `[Final Operator]` is computed — but `[Final Operator]`'s reference to it
  (`if(len(update_operator>0), update_operator, [ClaimOperator])`) is unreachable dead code because of
  the same always-true `len(x>0)` bug documented elsewhere, so its absence from the SQL is correct
  either way.

No further discrepancies found on this pass.

**Potential Hippo handoff point identified (not yet decided):** in both QUICKCHECK scripts, the
CTE chain splits cleanly into a "heavy" part (BRONZE table joins — `ClaimStatusMain` through
`Final` in `select_Claims_QUICKCHECK.sql`, or through `WithStringFields` in
`select_Total_QUICKCHECK.sql`) and a "light" part (pure aggregates/self-joins over that result, no
further BRONZE access). Both files now have a commented marker at that boundary
(`-- SELECT DISTINCT * FROM Final` / `WithStringFields`) noting that if Hippo materialises that
intermediate result as a table, everything below becomes a cheap view instead of re-running the
full join every time. Not decided: whether that table would also serve `select_Claims.sql` itself,
and whether `DISTINCT` belongs in the handed-off table (Qlik's own load chain does not dedupe at
that point, so omitting `DISTINCT` is the faithful-translation default) — needs a scope
conversation before acting on it.

---

## Total table validation (2026-09-08, in progress)

The Qlik "Summary" dashboard's left-side pivot (Row dimensions Operator/ClaimID/ServiceType/
ClaimKey; Measures Processed Claims / Verified Claims / Adjusted-Balanced Claims / Cancelled
Claims / Total / Avg No. Claims Processed Per Day / Claim Lines Processed) is driven by the `Total`
table (Qlik lines 647–771), which is out of scope as a deliverable (see Objects NOT Built above)
but was independently identified as one of 3 separate logic groups on that dashboard page (the
other two being the 12-number-card group already covered by `select_Claims_QUICKCHECK.sql`, and
the "Claim Lines Processed Today" pie chart, not yet started).

**Validation script:** `select_Total_QUICKCHECK.sql` — same VALIDATION-ONLY status as
`select_Claims_QUICKCHECK.sql` (not the deliverable, not for Hippo). Built from a trimmed subset of
`select_Claims.sql`'s CTE chain (Stages 1–5 for the operator-resolution fields, Stage 6 for
`MaxStatus`, Stage 11 for Adjustments) plus a from-scratch translation of the `Total` table's own
logic (4 of 5 Concatenate branches — Manual Claims omitted, not needed by the 6 measures below; 4
self-joins; the `AdditionalLogic` chain of derived flags). Covers 6 of the 7 dashboard measures
(all except Claim Lines Processed, whose Set Analysis expression has not yet been supplied). Output
is row-level (Operator, ClaimID, ServiceType, ClaimKey, Count Date, Type, and the 4 raw flag
columns each measure filters on) rather than pre-aggregated — per user decision, the actual
Processed/Verified/Adjusted/Cancelled/Total counts and the Avg No. Claims Processed Per Day ratio
are computed downstream in Excel/Power BI via distinct-count on `ClaimKey` (and `Count Date` for
the per-day ratio), not in SQL.

**Review process:** multiple rounds of line-by-line comparison against `claims_processing.md`
(647–771, plus the upstream `Claims`-building lines 185–599 this validation script re-derives a
trimmed version of) found and fixed 6 real defects before first execution:

1. `[Verified StatusCheck]` field was missing entirely. Qlik only defines this field on the main
   `claim_status` branch (line 221); the Concatenate'd `provider_claim_status` branch has no such
   field and Qlik leaves it NULL there. The script had substituted `[Verified Status Date] IS NOT
   NULL` as a proxy — but that field uses a *different* condition on the provider branch ('Sent to
   Medicare', line 249), so provider-sourced claims that should never match Qlik's actual
   `WildMatch([Verified StatusCheck],'Verified')` filter (line 669) were being incorrectly admitted
   into `Verified Claims`. Fixed by adding the field explicitly (NULL on the provider branch) and
   filtering on it directly.
2. `ProcessedLookup2` (the 4th self-join, Qlik lines 742–750) had an extra `DISTINCT` not present
   in the Qlik source (a plain `LOAD`, unlike the Adjusted join at line 732 which is `LOAD
   Distinct`) — meaning Qlik's join can fan out when a `ClaimID` has multiple distinct `Op` values
   among its 'Claims Processed' rows. Fixed by removing the `DISTINCT` to replicate the fan-out.
3. `TotalAdjusted`'s `Op`/`ClaimKey` used `[Adjusted Operator]` (the `AdjustedOperator` stage's
   ISNULL-fallback-to-`[Adj Create Operator]` derived field) instead of `[Adjusted Update
   Operator]` (the raw field Qlik line 676 actually reads, which can be NULL). Using the fallback
   would have wrongly replaced NULLs that Qlik's `Total` table leaves as NULL.
4. Fixing #3 surfaced a compile error (`Invalid column name 'Adjusted Update Operator'`) — the raw
   field was never threaded through `ClaimsWithAdjustments`/`WithStringFields` (only the
   ISNULL-fallback version was). Fixed by adding the raw field to the CTE's SELECT list. Not caught
   by 3 prior static-review passes — only surfaced once the user actually ran the script.
5. `VerifiedClaims`'s `[Verified Operator]` was a plain `cs.update_operator` passthrough, missing
   the SQL-SELECT-level pre-processing Qlik does at lines 272–277: `COALESCE(update_operator,
   create_operator)`, then truncate at the first `-` (not a simple 'ECLAIMS' substitution, unlike
   the main/provider branch pattern used elsewhere). Fixed by copying the already-verified pattern
   from `select_Claims.sql`'s `VerifiedClaims` CTE verbatim.
6. `AssessedClaims`'s `[Assessed Operator]` had the same class of gap — missing the truncate-at-`-`
   logic from Qlik line 294 (this one has no `COALESCE`, unlike Verified). Fixed the same way.

Findings 5–6 were only found on a full line-by-line pass that checked the SQL-SELECT-level
pre-processing inside the Qlik `LOAD ... ; SQL SELECT ...` blocks — a layer earlier static-review
rounds of this file had skipped, having focused on the `Total` table's own 4 branches and the
`AdditionalLogic` derived flags. Several rounds of re-review after fixes 1–6 (auto-join key
verification for all `Left Join (Total)` self-joins — each has a *different* implicit join key
depending on which fields the Qlik LOAD re-emits vs. renames/comments out; `OperatorMap` call-site
audit across all 6 usages; `ClaimKey` concatenation order/type-conversion check; Qlik's 3-layer
`AdditionalLogic` LOAD execution order re-derived and cross-checked against the CTE order) found no
further issues.

### Follow-up (2026-09-09): same `[Final Operator]`/`VerifiedOperatorCheck` ApplyMap-default bug found here too, plus a `CONCAT`-NULL bug in both files' fixes

A full re-comparison of `select_Total_QUICKCHECK.sql` against `claims_processing.md`, prompted by the
same bug class found in `select_Claims_QUICKCHECK.sql` (see the Runtime Validation section's
Follow-up (2026-09-09) entries above), found `ClaimsWithOperators3` had the **identical** mistake in
**two** fields, not one — this CTE was built independently of the Claims file's version and never had
the earlier fix applied:

- **`[Final Operator]`** (Qlik line 327, 2-arg `applymap('OperatorMap', ...)`, no default) — SQL fell
  back to `co2.FinalOperatorLookupCode` (the raw value) on a lookup miss instead of `NULL`.
- **`VerifiedOperatorCheck`** (Qlik line 329, `applymap('OperatorMap',[VerifiedOperator])`, also 2-arg
  no default, wrapped in an outer `if(match(VerifiedStatus,'Verified'), ..., 'No Operator')` — the
  `'No Operator'` fallback only fires when `VerifiedStatus <> 'Verified'`; it does NOT catch an
  ApplyMap miss when `VerifiedStatus = 'Verified'`) — SQL fell back to `co2.VerifiedOperator` (the raw
  value) on a lookup miss instead of `NULL`.

Fixed both by removing the raw-value fallback so a lookup miss produces `NULL`, matching Qlik's
no-default ApplyMap semantics.

**A second, subtler bug was found while applying this fix, in both files.** The straightforward-looking
fix (`CASE WHEN op.oper_name IS NULL THEN NULL ELSE CONCAT(op.first_name,' ',op.surname) END`) was
initially written without the `IS NULL` guard, as just `CONCAT(op.first_name, ' ', op.surname)`
unconditionally — reasoning that a failed LEFT JOIN leaves `op.first_name`/`op.surname` NULL, so
`CONCAT` "should" produce NULL too. This is wrong: **T-SQL's `CONCAT()` treats NULL arguments as empty
strings**, so `CONCAT(NULL, ' ', NULL)` returns `' '` (a single space string), not `NULL` — unlike
plain `+` string concatenation, which does propagate NULL. Both this file's fix and the earlier fix in
`select_Claims_QUICKCHECK.sql`'s `ClaimsWithOperators3` had this mistake; both were corrected to
explicitly test `op.oper_name IS NULL` and return a literal `NULL` rather than relying on `CONCAT`'s
NULL-handling. The two `Adjustments` CTE fields that also use `CONCAT(op.first_name,' ',op.surname)`
(`[Adjusted Update Operator]`, `[Adj Create Operator]`) were checked and are unaffected — Qlik's
source calls for those (lines 492/513) are genuinely 3-arg `Applymap(..., X, X)` with the raw value as
an explicit default, so falling back to the raw value on a miss is correct there, not a bug.

The rest of this file — all 4 `Total`-branch WHERE filters (`TotalProcessed`/`TotalVerified`/
`TotalAdjusted`/`TotalCancelled`, re-checked field-by-field against Qlik lines 647–693), the
Adjustments join's `[Claim ID]`-only key (re-derived from the full Adjustments field list — confirmed
`[Claim Line]` is a genuinely new field name at that point, not a hidden join key, and the WHERE-style
date filter Qlik applies before the join is correctly placed in the SQL join's `ON` clause rather than
a post-join `WHERE`, which would have wrongly turned the `LEFT JOIN` into an `INNER JOIN`), all 4
self-join keys (re-derived from scratch a second time, same conclusions as the first pass), and the 6
`AdditionalLogic` derived-flag formulas (`ProcessedCheck`/`ProcessedCheck3`/`AdjustedOnlyCheck`/
`ProcessedVerifiedCheck`/`ProcessedCheck2`/`VerifiedOnlyCheck`, including Qlik's bottom-up stacked-LOAD
execution order re-confirmed and matched against the `Final`→`Final2`→`Final3` CTE layering) — were
all re-checked and found correct. No further discrepancies found. Not yet re-run against the
dashboard's Totals row.

**Executed successfully** (2026-09-09): ran to completion twice, ~3.8–4.0M rows at the
`WithStringFields` stage (the pre-`Total`-logic intermediate) depending on whether `DISTINCT` is
applied there. Not yet aggregated into the 6 target measures for comparison against the dashboard's
"Totals" row (1,158,421 / 13,733 / 4,322 / 73,095 / 1,249,571 / 1,905) — that comparison is the next
step, done downstream (Excel/Power BI) per the row-level output design above, not in SQL.

**Known limitations:**
- Runtime is high (~6–27 min depending on where `DISTINCT` is applied and how much of the `Total`
  self-join logic runs) — not guaranteed to be faster than `select_Claims.sql`, since despite
  dropping fields `Total` doesn't need, this script adds `Total`'s own 4-branch UNION ALL + 4
  self-joins on top, which `select_Claims.sql` doesn't have. See the Hippo handoff-point note above
  for a way to cut this down once decided.
- `WithStringFields` itself contains ~2–3.5% fully-duplicate rows (confirmed via `SELECT DISTINCT`
  row-count comparison, 2026-09-09) — most likely from `ClaimDetailGenAndHosp` INNER JOIN
  `ClaimDetailsAtService` matching more than one `ClaimDetailsAtService` row per
  `claim_id`+`claim_line_id`. Not yet root-caused with a direct query. Benign for the 6 target
  measures (all use `distinct ClaimKey`, which absorbs exact-duplicate rows), but relevant if
  `WithStringFields` / a materialised version of it is ever consumed by something that isn't
  distinct-counting.
- Uses the same 13-month `@vStartDate` window as `select_Claims_QUICKCHECK.sql`. Given the
  confirmed window-width sensitivity of `[Bucket Type]`-driven Claims measures (see Follow-up
  above), `Total`'s counts — which similarly depend on claims resolved via `MaxStatus`/`[Final
  Operator]`/Adjustments over the same window — may show a similar gap against the dashboard;
  not yet tested.
- The Manual Claims branch (Qlik lines 695–705) is not implemented — none of the 6 measures
  currently covered need it, but a future 7th measure (Claim Lines Processed) or a Manual-Claims-
  specific check would need it added.

---

## Open Questions / Next Steps

**Settled (kept for history):**
- Step 2 (nested view dependency check) — skipped as not applicable; SQL usage is identical whether
  a BRONZE object is a table or a view.
- Step 3 (file naming) — settled: `select_Claims.sql`.
- Step 4 (data type discovery) — done for the core join/date/operator columns (see the type table
  above); the remaining columns are covered by the "needs execution" list below instead.
- Step 5 (CREATE TABLE draft) and Step 7 (Stored Procedure draft) — **skipped**, out of scope for
  this project (Hippo's responsibility, see Output scope / Ownership above).

**Still open — requires actual execution, not further static review** (see the pass 9/10/11 review
notes above for the full reasoning: static review reached diminishing returns after 44 fixes across
11 passes):
- ~30 BRONZE column names referenced but never independently confirmed to exist (e.g.
  `Product_Description`, `Num_services`, `Product_Description_at_claim`, `manual_flag`,
  `letter_subject`, `form_category`, `branch_group_id`).
- Whether `operator.oper_name` is `NOT NULL`.
- Whether `operator` has duplicate `(first_name, surname)` pairs (would row-multiply the `[Branch]`
  lookup — a documented, unfixed low-risk limitation).
- Row-count sanity check against the Qlik app's actual `Claims` table output, once available.
- The general question of whether the query actually runs and returns sane data — has not yet been
  executed even once.
