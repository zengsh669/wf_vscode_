# Membership New — DWH Design

## Overview

Scope is **not** a full translation of `membership_new.md`. The Qlik script builds a large
multi-table membership analytics model (MemberHistory, MemberStats, Ambulance model,
Retention Rates, Targets, Leads, Calendars, etc.), but this project only needs to
reproduce two specific report outputs the business asked for:

1. **Sales Channel Targets** — Joins/Terminations (actual vs target) and Annual Premium,
   grouped by Sales Channel Group, monthly, Jun 2015–Jun 2027.
2. **Joins by Operator** — Joins count, Joins Avg Premium, Total Annual Premium, grouped
   by Operator.

Both screenshots exclude Ambulance. Reference screenshots provided by user during design
discussion (not stored in repo).

**Status:** validation query built and iterated (`validate_membership_movement.sql`) —
covers Joins/Terminations/Net Growth by Sales Channel Group (screenshot 1, minus Targets/
Premium) and Joins by Operator (screenshot 2, minus Premium), for both historical
(`Membership_Group_Key`) and current-month (`BRONZE.dbo.memship`) slices symmetrically.
Not yet formalized as a GOLD view/SILVER table — still a validation query pending
resolution of Premium/Targets sourcing and the open verification gaps below. See
[Known Gaps Summary](#known-gaps-summary) for the current punch list.

---

## Column-by-Column Buildability (both screenshots)

Every column in both screenshots checked against confirmed sources. Historical and
current-month slices are symmetric — whatever is resolved/blocked for one is resolved/
blocked for the other, because both ultimately trace to the same underlying sources
(`Membership_Group_Key` for historical, `BRONZE.dbo.memship` + `Latest_Promo_Sales_Channel_By_Person`
for current-month — see [Historical vs. Current Month](#historical-vs-current-month)).

**Screenshot 1 — Sales Channel Targets:**

| Column | Buildable now? | Blocked by |
|---|---|---|
| Sales Channel Group | ⚠️ Revised — see [Sales Channel Group Rebuild](#sales-channel-group-rebuild) | — |
| Joins (count) | ✅ Yes | — |
| Terminations (count) | ✅ Yes | — |
| Net Growth (= Joins − Terminations) | ✅ Yes | — |
| Total Members at Point | ⛔ Removed from scope (user decision) | See [Total Members at Point — REMOVED from current scope](#total-members-at-point--removed-from-current-scope) |
| Joins Target | ❌ No | Open Question #1 (Targets source) |
| Terminations Target | ❌ No | Open Question #1 |
| Net Growth Target | ❌ No | Open Question #1 |
| Total Annual Premium – Joins | ❌ No | Open Question #2 (Premium source) |
| Total Annual Premium – Terminations | ❌ No | Open Question #2 |
| Net Annual Premium | ❌ No | Open Question #2 |
| Total Annual Premium – All Memberships | ❌ No | Open Question #2 |

**Screenshot 2 — Joins by Operator:**

| Column | Buildable now? | Blocked by |
|---|---|---|
| Operator | ✅ Yes | — |
| Joins (count) | ✅ Yes | — |
| Joins Avg Premium | ❌ No | Open Question #2 |
| Total Annual Premium – Joins | ❌ No | Open Question #2 |

**Summary:** every count/grouping column (no "Premium" or "Target" in the name) is
buildable today. Every column with "Premium" in the name is blocked on Open Question #2.
The 3 "Target" columns in screenshot 1 are blocked on Open Question #1, unrelated to
Premium or to the historical/current-month split.

---

## Scope Decisions

| Decision | Detail |
|---|---|
| Not a full port | Only the fields needed for the 2 target reports are in scope — MemberStats' Cover/Product/Age/LOM cohort logic, MonthlyRetentionRates, CoverChangeModel, Leads, and the entire Ambulance (`AMB*`) model are **out of scope**. |
| Cutover date | **Superseded — no date floor is applied.** Originally decided to scope to 2023-07-01 onward only, to avoid Qlik's pre-07/2023 "Old Logic" branch for Agent/Sales Channel Group (`AgentMap`/`PromoMap`, frozen June-2023 QVD snapshot). Re-examined after a 110-person Operator discrepancy investigation: Qlik's `MonthYear > MakeDate(2023,06,30)` (`membership_new.md:684-686`) is a **branch selector for which Sales Channel Group/Agent calculation to use**, not a row filter — Qlik counts Joins/Terminations across its *entire* history (screenshot title: "Jun 2015 to Jun 2027") regardless of which logic branch computed the grouping. Applying a 2023-07-01 floor to `Membership_Group_Key` was tested and made the Operator match *worse* (Laura Zammit: 2005 with floor vs 3443 without, vs screenshot's 3553) — confirming the floor was actively wrong, not just an unnecessary simplification. **Decision:** no date floor. Use all of `Membership_Group_Key`'s available history (2021 onward) as-is. **Accepted trade-off:** 2021 through 2023-06 will have its Sales Channel Group computed via this project's rebuilt logic (see [Sales Channel Group Rebuild](#sales-channel-group-rebuild)) rather than Qlik's actual Old Logic for that period (which depended on the frozen `AgentMap`/`PromoMap` snapshot and is not reproducible) — this was already an accepted gap under the original cutover decision, it just no longer means dropping the rows entirely. `validate_membership_movement.sql` was never actually updated to add a 2023-07-01 filter in the first place — this correction brings DESIGN.md in line with what the code has been doing since it was written, not a code change. |
| Sales Channel Mapping | **Superseded** — see [Sales Channel Group Rebuild](#sales-channel-group-rebuild). Originally decided that `Sales Channel Mapping.xlsx` would not be imported into SQL (Excel mapping applied in Power BI instead). Revisited after discovering `Membership_Group_Key`'s built-in Sales Channel Group logic uses a different, shorter Agent name-list than Qlik's and doesn't match the target screenshots. Decision reversed: the Excel mapping (47 rows) is now embedded directly in SQL as a `VALUES` CTE. |
| Historical data (pre-cutover / pre-SQL-rebuild) | Anything not reproducible from current BRONZE/SILVER sources (see Open Questions) will be exported once from the existing Qlik app as a static historical archive, since it will never change. SQL Server only needs to produce data going forward from the cutover point. |

---

## Open Questions

These are blocking full design of the Silver table(s) — user is confirming with colleagues.

| # | Question | Why it matters | Status |
|---|---|---|---|
| 1 | Where do `Joins Target` / `Terminations Target` come from? Qlik source is `MembershipMovements_SCTargets*.qvd` (business-maintained target values, not derived from Paragon). | Two columns in the Sales Channel Targets screenshot. If the source turns out to be an Excel file, user will import it directly into Power BI rather than SQL. | Open |
| 2 | Where does Annual/Weekly Premium come from? Qlik source is `ProductPremium_View_Transformed.qvd`. | Drives ~half the columns across both screenshots (Total Annual Premium – Joins/Terminations, Net Annual Premium, Joins Avg Premium). Deemed too significant to leave blank permanently — must be resolved, but work can continue in the meantime with it left blank. | Open — candidate found, see below |
| 3 | What generates `MemberHistory.qvd` (source of Qlik's monthly Join/Termination snapshot comparison)? Is it reproducible from Paragon/BRONZE, or is it itself a frozen extract? | Determines whether the Join/Termination monthly logic can be rebuilt natively in SQL going forward, or whether more of the history needs to be a one-time Qlik export. | **Resolved (historical months)** — see below |
| 4 | Does `SILVER.dbo.Latest_Promo_Sales_Channel_By_Person` already filter to `relationship = 1` (primary member only), matching Qlik's explicit filter (`membership_new.md:1069`)? | Confirms whether the Operator join needs an extra filter added on the SQL side. | **Resolved** — see below |

### Question 4 — Resolved

Reviewed `usp_Load_Latest_Promo_Sales_Channel_By_Person` (the SP that loads this SILVER
table). It selects `person_membership.relationship` through into the table as-is but
applies **no filter** on it — the table holds all relationships (primary members and
dependants), not just primary members. Confirmed by reading the SP body directly; no SQL
was run (VSCode has read-only DB access per project convention — see [project_ssms_write_access](../../../../../../.claude/CLAUDE.md)).

**Decision:** any query against `SILVER.dbo.Latest_Promo_Sales_Channel_By_Person` for this
project must add `WHERE Relationship = 1` explicitly, to match Qlik's filter.

### Question 3 — Resolved (historical months)

Qlik's own comment (`membership_new.md:1725`) says `MemberHistory.qvd` "is generated in
the profitability qvd generator using the group key report" — i.e. it's built by a
*separate* Qlik app, not by `membership_new.md` itself, from `group_key_full_by_branch`
data (same source table referenced by `ProductStringMap`, `membership_new.md:87-90`).

User found the SQL-native equivalent of that generator already exists:
`SILVER.dbo.Membership_Group_Key`, loaded by SP `dbo.Membership_Group_Key_Load`
(`@StartYear` param, defaults to 2021). It reads `BRONZE.dbo.group_key_full_by_branch`,
uses `LAG()` per `membership_id` to carry forward unchanged fields month-to-month, and a
`FULL OUTER JOIN` (current month vs. prior month + 1) to derive `memship_status`:
`'J'` = Join, `'T'` = Termination, else carried-forward status (mirrors Qlik's
`OUTER JOIN` + null-check pattern in intent, not literal SQL). It also carries
`sales_channel_description` / `sales_channel_group` with the Corporate-grouping logic
**already built into the SP** (CASE WHEN on `agent_description`) — meaning Sales Channel
Group does not need the Excel mapping applied for data sourced from this table.

**This resolves historical months only.** `Membership_Group_Key_Load` defaults to
`YEAR(rundate) >= 2021`, not 2015 — years before that (if in scope) still need a one-time
Qlik export, same as the pre-2023-07 cutover data. See [Historical vs. Current Month](#historical-vs-current-month) below for the other half of the gap (the still-open current-month problem).

**Correction:** the Sales Channel Group grouping logic built into `Membership_Group_Key_Load`
(CASE WHEN on `agent_description`) was initially assumed to be usable as-is. It is
NOT — see [Sales Channel Group Rebuild](#sales-channel-group-rebuild) below for why and
what replaces it. `Membership_Group_Key` is still the correct source for Join/Termination
counts and for the raw `Agent`/`Sales Channel` columns that the rebuild reads from; only
its own built-in *grouping* is being replaced.

---

## Sales Channel Group Rebuild

**Problem found:** `Membership_Group_Key`'s built-in `Sales Channel Group` column (CASE WHEN
on `agent_description`, 5 Agent values recognized) does not match Qlik's actual logic
(`membership_new.md:707-711`), which checks a much longer hand-written Agent list (~24
entries, e.g. `'Biloela Agency'`, `'Dysart Agency'`, `'Katoomba Agency'`, plus a wildcard
`'*Parkes Agency*'`) before falling through to `'Corporate'`. Running validation with the
table's own grouping produced categories that don't match the target screenshot at all
(e.g. `'CTM'`, `'Westfund Staff'`, `'Other'` as top-level groups instead of `'Compare the
Market'`, `'Previous Aggregator'`, `'No Channel Group'`, etc.).

**Two-step Qlik logic, reconstructed:**
1. Check whether `Agent` is in the hand-written list (`membership_new.md:707-710`). If yes
   → look up `Sales Channel` in the Excel mapping (`Sales Channel Mapping.xlsx`, 47 rows,
   `[Sales Channel] → [Group]`), defaulting to `'No Channel Group'` if no match. If Agent is
   NOT in the list → hard-coded `'Corporate'`, Excel is never consulted for these rows.
2. The Excel step only ever applies to the "in-list" Agents — it does not decide who is
   Corporate; the hand-written list does that.

**Excel content confirmed and embedded directly in SQL** (user provided full 47-row content
from `Sales Channel Mapping.xlsx`, confirmed as the correct file — not a `NEW` variant).
Given the small size (47 rows, 2 columns), it's embedded as a `VALUES` table constructor in
a CTE rather than imported as a table — no separate import/maintenance object needed.

**Agent field usability confirmed:** ran
`SELECT Agent, COUNT(*) FROM SILVER.dbo.Membership_Group_Key WHERE [Membership Status]='J' GROUP BY Agent`
— nearly all of Qlik's hand-written list values appear verbatim in `Membership_Group_Key.Agent`
(`No Agency`, `Westfund Staff`, `Finder`, `Telephone Sales`, `CTM`, `Choosi`, `Web Join`,
`Dysart Agency`, `Katoomba Agency`, `John Small Brokerage`, `Wellington Agency`, `Blackwater`,
`Rylstone Agency`, `Blackwater Agency`, `HICA Agency`, `Moura Agency - First National`,
`Biloela Agency`). A few from the Qlik list (`Covad`, `Kalgoorlie Agency`, `Sarina Agency`,
`Union Shopper`) don't appear at all in the 2021+ data — not a data problem, just no Joins
from those agencies in this date range. The table also contains a large number of Agent
values NOT in Qlik's list (sports clubs, corporate partners, councils — e.g. `Canterbury
Bulldogs Player` 517, `BHP Billiton Employee` 152) — these correctly fall through to
`'Corporate'` under the "not in list" rule; this is expected growth in corporate
partnerships since the Qlik list was last hand-maintained, not a translation error.

**Validated end-to-end** — ran the full two-step CTE (hand-written list + `LTRIM/RTRIM`-
normalized Excel join, `'*Parkes Agency*'` handled as `LIKE '%Parkes Agency%'` since it's a
Qlik wildcard, not an exact match) against historical Joins (2021+, Ambulance/Overseas
excluded). Result groups now match the screenshot's category names and are in the right
order of magnitude (e.g. `Web` 16427 vs screenshot 17263, `Phone` 14546 vs 16159, `Compare
the Market` 13053 vs 14431, `Corporate` 7801 vs 12136) — a large improvement over the
`Membership_Group_Key` built-in grouping, though not an exact match (see below).

**Root cause of the remaining gap — investigated, not a logic bug:**
`'No Channel Group'` came out as the single largest category (22642 in the SQL result).
Broke it down by `Agent`/`Sales Channel Raw`:
- 22613 of those 22642 (99.9%) are `Agent = 'No Agency'` with `Sales Channel` = **NULL** —
  these members are in the hand-written list (so Excel should apply), but
  `Membership_Group_Key.[Sales Channel]` itself has no value recorded for them, so there's
  nothing for the Excel mapping to look up. This is a data-completeness gap in
  `Membership_Group_Key` itself, not a mapping or list error.
- The remaining ~29 rows have `Sales Channel Raw = 'Corporate'` for Agents like `Dysart
  Agency` / `John Small Brokerage` — the literal string `'Corporate'` never appears in the
  Excel's Sales Channel column, so these can't match either. Likely a data quality quirk
  (Sales Channel field holding a value that looks like a grouping label, not a channel
  name) — small volume, not investigated further.

**Root cause found — isolated to 2021, not a general data-completeness problem.** Checked
whether the NULLs were spread evenly or concentrated:

```sql
SELECT CASE WHEN [Sales Channel] IS NULL THEN 'NULL' ELSE 'Has Value' END AS Sales_Channel_Status, COUNT(*) AS Cnt
FROM SILVER.dbo.Membership_Group_Key WHERE [Membership Status] = 'J'
GROUP BY CASE WHEN [Sales Channel] IS NULL THEN 'NULL' ELSE 'Has Value' END;
-- Has Value: 73016   NULL: 27171  (27% overall NULL rate)
```

Broken down by year:

| Year | Total Joins | NULL Sales Channel | NULL % |
|---|---|---|---|
| 2021 | 66208 | 26960 | **40.7%** |
| 2022 | 7171 | 29 | 0.4% |
| 2023 | 7193 | 39 | 0.5% |
| 2024 | 7820 | 76 | 1.0% |
| 2025 | 7464 | 36 | 0.5% |
| 2026 | 4331 | 31 | 0.7% |

99.2% of all NULLs (26960/27171) are in 2021 alone — the year `Membership_Group_Key_Load`'s
`@StartYear` parameter defaults to, i.e. the first year of this table's backfill. From
2022 onward the NULL rate is under 1%, effectively normal. This strongly suggests the 2021
backfill itself has a systemic Sales Channel data gap (likely from how that first year was
bulk-loaded/backfilled), not an ongoing per-member data quality issue and not something
wrong with the CTE/mapping logic built in this project.

**Practical implication:** 2022 onward, the Sales Channel Group rebuild should be close to
fully accurate. 2021 specifically will show an inflated `'No Channel Group'` count due to
this backfill gap — not yet decided whether that's acceptable (dilute across all years,
exclude 2021, or investigate the backfill further) — pending user decision once other
open items are cleared.

**Still not checked:** whether Qlik's own `MemberHistory.qvd` has the same 2021 gap (would
confirm this is a genuine source-data limitation shared by both systems, not a
`Membership_Group_Key`-specific defect) — no access path to Qlik data confirmed yet for
this comparison.

**Gap identified, NOT implemented (deliberately deferred):** Qlik's actual field lookup for
Sales Channel isn't just `SalesChannelTMP` — it's `Coalesce(SalesChannelTMP,[Old Sales
Channel])` (`membership_new.md:711`, and again at `:728-729` for the raw `[Sales Channel]`
column) — i.e. if the current month's Sales Channel is blank, Qlik falls back to *last
month's* value for that member before defaulting to `'No Channel Group'`/`'No Channel'`.
This project's rebuild (both historical and current-month CTEs in
`validate_membership_movement.sql`) reads only the current-period value with no such
fallback — a genuine gap against Qlik's logic, missed when the two-step Corporate/Excel
logic was first built (attention was on the `WildMatch` Agent-list branch, not this nested
`Coalesce` inside the Excel-lookup argument).

**Tested whether this gap explains the 'No Channel Group' mismatch — it does not, and the
direction is backwards from what was assumed:** compared this project's Query 1 output
against the screenshot: `No Channel Group` Joins are **22643 here vs 26130 in Qlik**
(lower, not higher) and Terminations **3621 here vs 8896 in Qlik** (also lower). A missing
fallback should, if anything, shift members *out* of `No Channel Group` once implemented
(recovering a channel value from last month), which would only widen this gap further, not
close it — so this is not the explanation for the mismatch, and implementing the fallback
is not expected to improve alignment with the screenshot. Root cause of the `No Channel
Group` undercount itself is still unexplained.

**Decision: record but do not implement for now.** The `Coalesce(current, previous)` gap is
real per Qlik's source, but not a priority fix given it doesn't address the actual observed
mismatch. Revisit if/when doing a more thorough Sales Channel fidelity pass.

**Scope note — UPDATED, current month now also rebuilt.** Originally this rebuild was
historical-only, with current month deferred pending an Agent source. That source has since
been found and implemented: `BRONZE.dbo.MemberAgent` (`membership_id` → `group_id`/
`description`), confirmed as the SQL-native equivalent of Qlik's `Paragon_MemberAgent.qvd`
(`membership_snapshots.md:120-125` — same fields, plain unconditional `LEFT JOIN` with no
filter in Qlik). Confirmed via `SELECT membership_id, COUNT(*) ... HAVING COUNT(*) > 1` that
`BRONZE.dbo.MemberAgent` has exactly one row per `membership_id` (no duplicates), matching
Qlik's unfiltered join — no `termination_date` filtering needed. The current-month CTE chain
in `validate_membership_movement.sql` now joins `MemberAgent` and applies the identical
two-step (hand-written list → Excel lookup → `'Corporate'` fallback) logic used for
historical. Both slices are now symmetric for Sales Channel Group. Re-ran Query 1 after this
change: results shifted only slightly (e.g. `Corporate` 7711→7758, `Web` 16186→15920) —
expected, since one month of current-month data is small relative to 5+ years of history.

**Alternative approach seen in an existing official GOLD view (noted, not adopted):**
`GOLD.dbo.Membership_Reporting` (found alongside `GOLD.dbo.Membership_Movement`, both
built on `SILVER.dbo.Membership_Group_Key`) uses the table's own built-in `[Sales Channel
Group]` column directly, with no rebuild — just `ISNULL([Sales Channel Group],'Other')` as
a NULL fallback. This is the simpler, one-step approach this project rejected earlier
(see the "Problem found" note above — `Membership_Group_Key`'s built-in grouping uses a
shorter, different Agent list than Qlik's, and testing showed it produces category names
that don't match the target screenshots, e.g. `'CTM'`/`'Westfund Staff'`/`'Other'` instead
of `'Compare the Market'`/`'Previous Aggregator'`/`'No Channel Group'`). **Decision: keep
this project's two-step rebuild** (closer to Qlik, already validated against the
screenshots) rather than switching to match the existing official view's simpler pattern —
recorded here for awareness in case future work needs to reconcile with
`Membership_Reporting`/`Membership_Movement`'s approach.

**Note on 2021 gap relevance:** the 2021 Sales Channel gap above was investigated before
realizing 2021 was never actually excluded by any date floor — the "Cutover date" scope
decision (2023-07-01 onward) was never implemented in code, and has since been reversed
(no date floor at all, see below). So 2021 rows ARE included in the historical result and
this gap is a real, live factor in the current numbers — not moot.

**`SILVER.dbo.Termination_Code` — noted, not needed.** `GOLD.dbo.Membership_Reporting`
joins this table to derive `[Termination Reason]` detail. Checked whether Qlik's own
`membership_new.md` has equivalent Termination Reason logic that would put this in scope:
it does (`membership_new.md:932-940`, `MonthlyRetentionRatesTmp`, and `:1176-1210`,
`MembershipTerminations`), but both live inside modules already explicitly out of scope for
this project (see [Objects NOT Built](#objects-not-built-by-design) — Retention Rates
and — Terminations detail was never carried into the two target screenshots, which only
need a Terminations **count**, not reason/detail). No action needed; not joining
`Termination_Code` in `validate_membership_movement.sql`.

---

## OVHC (Overseas Visitor Health Cover) Exclusion

**Not in Qlik's `membership_new.md` at all** — discovered from two unrelated existing GOLD
views (`GOLD.dbo.Membership_Reporting`, `GOLD.dbo.Membership_Movement`) that the user shared
mid-project, both built on `SILVER.dbo.Membership_Group_Key`. `Membership_Reporting`
excludes members via:
```sql
WHERE NOT EXISTS (
    SELECT 1 FROM BRONZE.dbo.group_key_full_by_branch B
    WHERE B.membership_id = M.[Membership Number]
    AND B.hosp_product_id IN (191, 192, 193, 194, 195, 196)
    AND B.extras_product_id IS NULL
)
```
User confirmed via query that these 6 IDs are `BRONZE.dbo.product.product_id` values for the
"Overseas Workers" Hospital product range (`OWEA`/`OWEB`/`OWSA`/`OWSB`/`OWCA`/`OWCB`, all
`product_type = 'H'`) — same numbering system as `group_key_full_by_branch.hosp_product_id`,
safe to reuse. **User decided to adopt this exclusion**, even though it has no Qlik-side
justification found in `membership_new.md` — added to both historical and current-month
slices in `validate_membership_movement.sql`.

**Historical:** reuses the exact pattern above (`group_key_full_by_branch`).

**Current month:** cannot reuse `group_key_full_by_branch` — confirmed via
`SELECT MAX(rundate) FROM BRONZE.dbo.group_key_full_by_branch` that its latest row (e.g.
`2026-08-01`) reflects **prior month-end state** (e.g. 2026-07-31 per user confirmation),
not current-month-to-date activity — a member who joined this month wouldn't have a row
there yet. Instead built a `CurrentMonthOVHC` CTE using the same live
`cover`/`cover_product`/`product` tables as the current-month Ambulance exclusion: latest
`cover_version` with a Hospital product (`product_type='H'`) whose `product_id` is in
(191-196), and a `NOT EXISTS` check that no Extras (`product_type='A'`) product is attached
on the same `cover_version` (mirroring the historical side's `extras_product_id IS NULL`).

**Not cross-validated:** the historical (string/ID field match on `group_key_full_by_branch`)
and current-month (live `cover`/`cover_product`/`product` join) exclusion paths for both
Ambulance and OVHC are expected to be logically equivalent but have never been tested against
the same known cases to confirm they actually produce identical membership sets.

---

## Operator NULL Gap

Both Query 2 (Joins by Operator) results show a large `NULL` Operator row (e.g. 48885
Joins) — records where no matching `Relationship = 1` row exists in
`SILVER.dbo.Latest_Promo_Sales_Channel_By_Person` for that `membership_id`. Investigated by
sampling: for a batch of historical Joins with no match at all, most `Relationship = 1` rows
(the primary member) had no `promotion_reference` record, while a `Relationship = 2/4/5`
row (a dependant) on the *same membership* sometimes did. I.e. promotion/Operator data is
sometimes recorded against a dependant rather than the primary member, and since Qlik's own
logic (`membership_new.md:1069`) filters to `relationship = 1` only, those Joins correctly
end up with no Operator under a faithful translation — **this is expected behavior given
Qlik's filter, not a bug**, but it means the Operator breakdown will always undercount
against a hypothetical "every Join has an Operator" view. Not further investigated or
addressed — recorded here for visibility since it materially affects how complete Query 2's
Operator list looks.

---

## `rundate` vs `[Run Month]` Bug — Fixed

**Found:** `SILVER.dbo.Membership_Group_Key` has two date columns — `rundate` (the batch-run
timestamp, e.g. `2026-08-01`) and `[Run Month]` (the actual business month that row
represents, e.g. `2026-07-31` for that same row — confirmed via
`SELECT TOP 5 rundate, [Run Month] FROM ... ORDER BY rundate DESC`). This offset comes from
`Membership_Group_Key_Load`'s own source computation:
`EOMONTH(DATEADD(day,-1,COALESCE([group_key].[rundate],...)))` — the SP itself derives
`runmonth` as "one day before `rundate`, rounded to month-end", i.e. `rundate` is always one
calendar day into the *next* month relative to what it represents.

`validate_membership_movement.sql` originally filtered/grouped historical rows on
`gk.rundate < @CurrentMonthStart`. Because of the offset above, this silently **excluded an
entire month's worth of real data with no error and no NULLs** — the most recently completed
month (e.g. July 2026) fell into neither slice: historical excluded it via this `rundate`
filter (since its `rundate` value, `2026-08-01`, is not `< 2026-08-01`), and current-month
only covers August-to-date, never July. Confirmed the missing volume directly:

```sql
SELECT [Run Month], SUM(CASE WHEN [Membership Status]='J' THEN 1 ELSE 0 END) AS Joins,
       SUM(CASE WHEN [Membership Status]='T' THEN 1 ELSE 0 END) AS Terminations
FROM SILVER.dbo.Membership_Group_Key WHERE [Run Month] >= '2026-01-31'
GROUP BY [Run Month] ORDER BY [Run Month];
-- 2026-07-31: 577 Joins, 546 Terminations — a normal month's volume, previously absent
-- from every result this project produced.
```

**Fix:** every `gk.rundate` reference in `validate_membership_movement.sql` (both the
`SELECT ... AS MonthYear` and the `WHERE ... < @CurrentMonthStart` filter, in both Query 1's
and Query 2's CTE copies) switched to `gk.[Run Month]`. Not yet re-run/re-validated against
the screenshots since this fix — the ~3-7% Operator/Joins undercount figure documented
throughout this file (see [Cutover Date](#cutover-date--resolved-superseded-original-decision))
was measured *before* this fix, so the actual current gap is likely smaller now that a
previously-missing month is included, but hasn't been re-measured.

**Not fixed (separate, pre-existing issue, flagged not resolved):** the historical-side
OVHC exclusion (`NOT EXISTS` against `BRONZE.dbo.group_key_full_by_branch`, see [OVHC
Exclusion](#ovhc-overseas-visitor-health-cover-exclusion)) checks by `membership_id` only,
with no `rundate`/`runmonth` filter tying it to the specific `[Run Month]` row being
evaluated — it's a global "has this member ever had an OVHC product" check, not a per-month
one. This is a different, pre-existing simplification (inherited from the
`GOLD.dbo.Membership_Reporting` pattern this was borrowed from) — not introduced or
addressed by the `Run Month` fix above.

---

## Join/Termination Determination — Never Cross-Validated

`Membership_Group_Key`'s `[Membership Status]` values (`'J'`/`'T'`/carried-forward) are
used as a drop-in replacement for Qlik's own Join/Termination logic (comparing `Cover` to
`Old Cover` via a self-join, `membership_new.md:731-732`, see [Join/Termination
Logic](#jointermination-logic)). The two methods are believed to be logically equivalent in
intent, but **no row-level comparison has ever been done** — e.g. picking a sample of
members and manually confirming Qlik would classify them the same way this project's SQL
does. This is the foundational assumption everything else in this project sits on top of,
and it remains unverified.

---

## Cutover Date — Resolved (Superseded Original Decision)

While investigating a ~100-150-person-per-Operator discrepancy between this project's
Joins count and the Qlik screenshot (see [Total Members at Point](#total-members-at-point)
below for the investigation that led here), added a `rundate >= '2023-07-01'` filter to
test the originally-decided cutover. Result: Laura Zammit's Joins dropped to 2005 (vs 3443
without the filter, vs screenshot's 3553) — the filter made the match *worse*.

Re-read Qlik's actual logic (`membership_new.md:684-686`):
```
If(MonthYear > MakeDate(2023,06,30),[Sales Channel Group New Logic],[Sales Channel Group Old Logic]) as [Sales Channel Group],
If(MonthYear > MakeDate(2023,06,30),[Agent New Logic],[Agent Old Logic]) as Agent,
```
This is a **branch selector for which calculation method to use**, not a row filter. Qlik
counts Joins/Terminations across its entire available history regardless of which logic
branch computed the Sales Channel Group/Agent for that row — consistent with the screenshot
title "Jun 2015 to Jun 2027".

**Decision:** no date floor. Use all of `Membership_Group_Key`'s available history. Accept
that 2021 through 2023-06 gets this project's rebuilt Sales Channel Group logic rather than
Qlik's actual (non-reproducible) Old Logic for that period — this was already an accepted
gap under the original cutover decision, it just no longer means dropping those rows
entirely.

**Confirmed `Membership_Group_Key`'s actual date range** (not just the SP's default
`@StartYear` parameter, which only says what happens if no `@StartYear` is passed — could
differ from what's actually in the table depending on how the SP was last run):
```sql
SELECT MIN(rundate) AS Earliest_Rundate, MAX(rundate) AS Latest_Rundate, COUNT(DISTINCT rundate) AS Distinct_Rundates
FROM SILVER.dbo.Membership_Group_Key;
-- Earliest: 2021-01-01   Latest: 2026-08-01   68 distinct months
```
So `Membership_Group_Key` genuinely starts 2021-01-01 — 6 years later than Qlik's
"Jun 2015" screenshot range. This is the confirmed root cause of the remaining ~3-7%
Operator/Joins undercount (see `validate_membership_movement.sql` header for detail) —
**user decided to accept this gap**, not chase a pre-2021 data source.

`validate_membership_movement.sql` was never actually updated to add the 2023-07-01
filter — it has been using the full available history since it was first written. This
section brings DESIGN.md's stated decision in line with what the code has always done.

---

## Total Members at Point — REMOVED from current scope

**Status: intentionally removed, not abandoned.** Was built and validated for the
historical slice (point-in-time active count — different shape from Joins/Terminations,
counting distinct `membership_id` where `[Membership Status] IN ('A', 'J')`). Validated
reasonably well against the screenshot for 2026-07 (most groups within ~1-3%, e.g. `No
Channel Group` 17571 vs screenshot 17386; one outlier, `Previous Aggregator`, ~49% off,
not investigated).

**User decision:** remove this column from scope entirely (both historical and
current-month — current-month was never built anyway) to simplify the query while other
open items (Premium, Targets, current-month Sales Channel Group) are worked through.
**Can be added back later if the business confirms it's needed** — the validated logic
above (status `IN ('A','J')`, same Sales Channel Group grouping) is the starting point if
so; the `[Membership Status] IN ('A','J')` assumption was never fully verified against the
full distinct value list of that column, so re-verify before reinstating.

The combined query (Joins/Terminations/Net Growth + Total Members at Point in one GROUP BY,
since `Membership_Group_Key` is already one-row-per-membership-per-month grain) that had
been built for this is reverted — Total Members at Point is dropped from the SELECT list.

**Separately discovered while testing the combined query (worth revisiting later):** the
first month in `Membership_Group_Key` (2021-01, i.e. `Membership_Group_Key_Load`'s backfill
start month) shows a large Joins spike with zero Terminations across every group (e.g. `No
Channel Group` 22492 Joins / 0 Terminations that month alone) — consistent with the
backfill logic marking every pre-existing member as a `'J'` in its first month since there's
no prior month to compare against. This inflates 2021-01 Joins artificially and should be
excluded or handled separately if/when the query is revisited, but is not blocking current
work since Total Members at Point itself is out of scope for now.

---

## Decided Source Mappings

| Need | Confirmed Source | Notes |
|---|---|---|
| Operator (screenshot 2 grouping) | `SILVER.dbo.Latest_Promo_Sales_Channel_By_Person` (`WHERE Relationship = 1`) | Already in SILVER, not BRONZE — matches Qlik's `LatestPromoSalesChannelByPerson` (`membership_new.md:1062-1069`). |
| Sales Channel (raw, screenshot 1) | `SILVER.dbo.Latest_Promo_Sales_Channel_By_Person.Sales_Channel_Description` (`WHERE Relationship = 1`) | Same table as Operator — one join covers both screenshots' grouping needs. |
| Historical monthly Join/Termination + Sales Channel Group | `SILVER.dbo.Membership_Group_Key` (loaded by `dbo.Membership_Group_Key_Load`) | See Question 3 resolution above. Covers `rundate` from 2021 onward only. |
| Current-month Join/Termination | `BRONZE.dbo.memship` (no suffix, live current state) | See [Historical vs. Current Month](#historical-vs-current-month). |
| Current-month Agent (for Sales Channel Group rebuild) | `BRONZE.dbo.MemberAgent` (`membership_id` → `group_id`/`description`) | One row per `membership_id`, confirmed no duplicates. See [Sales Channel Group Rebuild](#sales-channel-group-rebuild) Scope note. |
| Ambulance exclusion (current month) | `BRONZE.dbo.cover` / `cover_product` / `product` (`product_type = 'B'`, latest `cover_version`) | See file header of `validate_membership_movement.sql`. |
| OVHC exclusion (historical) | `BRONZE.dbo.group_key_full_by_branch.hosp_product_id IN (191-196)` AND `extras_product_id IS NULL` | See [OVHC Exclusion](#ovhc-overseas-visitor-health-cover-exclusion). |
| OVHC exclusion (current month) | `BRONZE.dbo.cover` / `cover_product` / `product` (`product_id IN (191-196)`, `product_type='H'`, no `product_type='A'` on same `cover_version`) | See [OVHC Exclusion](#ovhc-overseas-visitor-health-cover-exclusion) — `group_key_full_by_branch` cannot be reused here (reflects prior month-end, not current month-to-date). |

---

## Historical vs. Current Month

Qlik's own script is structured in exactly this two-part shape, which the SQL rebuild
should mirror:

- **Historical months** (`MemberHistory`, `membership_new.md:415-457`) — closed, frozen
  monthly snapshots. **Resolved** — `SILVER.dbo.Membership_Group_Key` covers this
  (2021 onward; earlier years need a one-time Qlik export, per the cutover decision above).
- **Current month / month-to-date** (`CurrentMonthSnapshot`, `membership_new.md:460-503`)
  — a *separate* Qlik block reading a live "latest state" extract
  (`Membership_SnapShot_Latest.qvd`, not a monthly archive), filtered to members whose
  `Effective Join Date` has already passed or whose `Effective Termination Date` hasn't
  yet passed as of today. **Resolved** — see below.

### Current Month — Resolved

Traced `Membership_SnapShot_Latest.qvd` back to its generator: a separate Qlik app,
`membership_snapshots.md` (found by user in the Qlik hub, saved alongside this project as
`22_membership_new/membership_snapshots.md`). Read in full (2138 lines).

Its `Memberships` table (lines 104–291) builds the "current state as of right now" by
loading `Paragon_Memberships.qvd` (fields: `membership_id`, `fund_id`, `termination_code`,
`memship_status`, `effective_join_date`, `effective_termination_date`, `create_operator`,
`state` — line 106-117) plus several left-joined QVDs for Agent/Branch/Cover/Person/Fees,
then stores the result both to a dated file and to `Membership_SnapShot_Latest.qvd`
(lines 287-288) — overwritten daily. No historical accumulation logic; it's a same-day
extract-and-store, run once per day.

`Paragon_Memberships.qvd` is itself a QVD extract (not a direct SQL connection in this
script), so it doesn't literally prove which BRONZE table backs it. User confirmed BRONZE
has two forms of `memship`: `memship_YYYYMMDD` (permanent daily-dated snapshots) and
`memship` with no suffix (Type-1, truncate-and-reload daily — reflects current state only,
no history kept). User ran:

```sql
SELECT COLUMN_NAME, DATA_TYPE FROM BRONZE.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'memship' ORDER BY ORDINAL_POSITION
```

All 8 fields used by `Paragon_Memberships.qvd` (`membership_id`, `fund_id`,
`termination_code`, `memship_status`, `effective_join_date`, `effective_termination_date`,
`create_operator`, `state`) are present in `BRONZE.dbo.memship` (no suffix). Combined with
it being the "current state, no history" table — the same shape as
`Paragon_Memberships.qvd` — this is accepted as the SQL-native equivalent.

**Decision:** current-month/MTD Joins/Terminations are queried directly and live from
`BRONZE.dbo.memship` (no suffix), filtering on `effective_join_date`/
`effective_termination_date` falling in the current month — no separate snapshot table
needs to be built or maintained. `memship_YYYYMMDD` (dated snapshots) is **not** used for
this — it isn't needed since `memship` (no suffix) already gives live current state, and
per the earlier decision to follow the Qlik project file's own logic rather than adapt an
unrelated SP (see [Join/Termination Logic](#jointermination-logic)).

**Sales Channel for the current-month slice — already resolved, no new gap.**
`membership_snapshots.md`'s `Memberships` table sources Sales Channel from
`Paragon_PromoReference.qvd` + `Paragon_PromoSalesChannel.qvd` (lines 201-219, table
`TMPPROMO`) — the same shape as `SILVER.dbo.Latest_Promo_Sales_Channel_By_Person`
(`promotion_reference` + `promotion_sales_channel`, already confirmed as the source for
Operator/Sales Channel — see [Decided Source Mappings](#decided-source-mappings)). Same
table, same join key (`membership_id`), used for both historical and current-month slices.
(An earlier version of this section incorrectly listed Sales Channel as unresolved for the
current month — that was a mistake, not a change in the actual data situation; corrected
here.)

**Still open:** Premium (Weekly/Annual Total Premium) for the current-month slice — this is
the same unresolved Open Question #2 above, not a separate gap; `membership_snapshots.md`
computes it itself from `Paragon_Cover_Product.qvd` + `Paragon_Product_Fee.qvd` (lines
225-283), and no BRONZE/SILVER equivalent has been confirmed yet for either the historical
or current-month slice. Branch, Person Count, and detailed Cover/Product fields
(`Paragon_MemberCover.qvd`, `Paragon_MemberBranch.qvd`, `Paragon_PersonMembership.qvd`,
lines 120-167) are also unconfirmed but are **out of scope** — neither screenshot needs
them (see [Objects NOT Built](#objects-not-built-by-design)).

## Join/Termination Logic

Qlik determines Joins/Terminations by taking `MemberHistory.qvd` (one monthly snapshot
row per member) and self-joining it one month offset (`OUTER JOIN`, `membership_new.md:573-604`)
so each row also carries the *previous* month's values (`Old Cover`, `Old Product Code`, etc.).
A member is a **Join** if `Old Cover` is null (`membership_new.md:732`); a **Termination** if
the current month's `Cover` is null (`membership_new.md:731`).

For historical months, `SILVER.dbo.Membership_Group_Key`'s `memship_status` values
(`'J'`/`'T'`/carried-forward) are used directly instead of re-deriving via a fresh
self-join — same underlying idea (compare two point-in-time snapshots), already computed.
`Member_Daily_Movement` (`21_Membership_Reporting_Daily/usp_Load_Member_Daily_Movement.sql`)
was considered and rejected — it's a separate, unrelated object using **daily**
`memship_YYYYMMDD` BRONZE snapshots, not reused here per user instruction to follow the
Qlik project file, not that SP.

---

## Objects NOT Built (by design)

| Object / Field | Reason |
|---|---|
| MemberStats Cover/Product/Age/LOM cohort fields, Product Type/Tier/Excess Level, Anniversary logic, Cover Change (Upgrade/Downgrade) flags | Not shown in either target screenshot |
| `MonthlyRetentionRatesTmp` / `MonthlyRetentionRates` | Not needed for these 2 reports |
| `CoverChangeModel` | Not needed for these 2 reports |
| `Leads` | Not needed for these 2 reports |
| Entire Ambulance model (`AMBMemberHistory`, `AMBMemberStats`, `AMBMasterCalendar`, etc.) | Both screenshots are explicitly "Excludes Ambulance" |
| Pre-2023-07-01 Agent/Sales Channel "Old Logic" (`AgentMap`, `PromoMap`) | Out of scope per cutover decision above |

---

## Known Gaps Summary

Current punch list, most impactful first. All gaps are documented in detail in their own
sections above (linked) — this is a quick-reference index, not a replacement for reading
them before acting on any of these.

**Structural (columns not built at all):**
- Premium (7 of 16 total columns across both screenshots) — Open Question #2, blocked on
  business/colleague confirmation of source.
- Targets (3 columns, screenshot 1 only) — Open Question #1, blocked on business
  confirmation; likely goes straight to Power BI, not SQL, once confirmed.
- Total Members at Point — deliberately removed by user decision, not blocked, can be
  reinstated on request. See [Total Members at Point](#total-members-at-point--removed-from-current-scope).

**Unexplained data discrepancies:**
- `'No Channel Group'` Joins/Terminations run *lower* than the Qlik screenshot (not higher
  as initially assumed) — root cause still unknown. See [Sales Channel Group
  Rebuild](#sales-channel-group-rebuild).
- Overall Joins/Terminations run ~3-7% below Qlik — root cause confirmed and accepted
  (`Membership_Group_Key` starts 2021, Qlik data likely goes back to 2015). **This figure was
  measured before the `rundate`/`[Run Month]` fix below and has not been re-measured** — the
  actual current gap is likely smaller now. See [Cutover
  Date](#cutover-date--resolved-superseded-original-decision).
- Operator breakdown always undercounts vs. a hypothetical complete list, due to promotion
  data sometimes being recorded against a dependant rather than the primary member. Expected
  given Qlik's own `relationship = 1` filter, not a bug. See [Operator NULL
  Gap](#operator-null-gap).

**Fixed (was silently dropping data, now corrected):**
- `Membership_Group_Key.rundate` was being used as the month-grouping/filter field, but it's
  a batch-run timestamp offset by one day from the actual business month (`[Run Month]` is
  the correct field) — this silently excluded an entire month's real data (~577 Joins / 546
  Terminations for the most recently completed month) from every result. Fixed by switching
  to `[Run Month]` throughout. Not yet re-validated against the screenshots post-fix. See
  [`rundate` vs `[Run Month]` Bug](#rundate-vs-run-month-bug--fixed).

**Unverified assumptions (foundational, not yet tested):**
- Join/Termination determination via `Membership_Group_Key.[Membership Status]` has never
  been cross-checked row-by-row against Qlik's actual `Cover`/`Old Cover` self-join logic.
  See [Join/Termination Determination](#jointermination-determination--never-cross-validated).
- Historical vs. current-month Ambulance/OVHC exclusion paths (different source tables) have
  never been tested against the same known cases to confirm equivalent results. See [OVHC
  Exclusion](#ovhc-overseas-visitor-health-cover-exclusion).
- The historical OVHC exclusion is not month-aligned — it checks whether a member has *ever*
  had an OVHC product across all of `group_key_full_by_branch`, not specifically as of the
  `[Run Month]` being evaluated. Pre-existing, not introduced by the Run Month fix. See
  [`rundate` vs `[Run Month]` Bug](#rundate-vs-run-month-bug--fixed).
- `[Membership Status] IN ('A','J')` for Total Members at Point (if reinstated) was never
  checked against the full distinct value list of that column.

**Known but deliberately deferred (documented, not planned to fix soon):**
- Qlik's `Coalesce(current, previous month)` fallback for blank Sales Channel is missing
  from this project's rebuild — confirmed NOT to explain the `No Channel Group` mismatch, so
  low priority. See [Sales Channel Group Rebuild](#sales-channel-group-rebuild).
- 2021-01 (backfill start month) shows an artificial Joins spike with zero Terminations.
  Currently moot since Total Members at Point is out of scope, but will resurface if that
  column is reinstated or if a month-by-month breakdown is ever needed.

---

## Next Steps

1. User to confirm Open Questions #1 (Targets source) and #2 (Premium source) with
   colleagues — the two structural blockers above.
2. Decide whether to investigate the unexplained `'No Channel Group'` undercount before
   treating Sales Channel Group as reliable.
3. Once Premium/Targets are resolved (or explicitly deferred to Power BI), decide whether to
   formalize `validate_membership_movement.sql` into a permanent GOLD view, and whether the
   unverified assumptions above need to be closed out first or can ship with known-risk
   caveats.
