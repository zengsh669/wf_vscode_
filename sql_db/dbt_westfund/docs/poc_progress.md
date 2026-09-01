# dbt POC — Progress Notes

Last updated: 2026-09-02

## Goal

Evaluate dbt (dbt-core + dbt-sqlserver) as a replacement for SP-driven Silver
table loads, primarily to solve manual dependency ordering in ADF. Secondary
goal: auto-generated lineage. Scope narrows to only the Silver tables / Gold
views that are actually used, using this migration as a cleanup opportunity.

## Status: blocked on IT approval

Local environment is fully ready. The only blocker is Sandbox database
read/write access from VSCode — not yet requested/granted.

## Local environment — DONE

- Python 3.14, dbt-core 1.12.3, dbt-sqlserver 1.11.1 installed in
  `sql_db/dbt_westfund/.venv/`
- ODBC Driver 17 for SQL Server already present, no install needed
- Project scaffold created: `dbt_project.yml`, `models/sandbox/` (empty),
  `profiles.yml.example`
- `~/.dbt/profiles.yml` configured with placeholder credentials; `dbt debug`
  confirmed config/driver/profile parsing all pass — only the actual network
  connection fails (expected, since Sandbox access isn't granted yet)
- Committed to git (local only, not yet pushed)

## Planned deployment paths (not yet submitted to IT)

**Python/dbt path:** Sandbox dev/test → Jira ticket → point config at Silver
→ commit to ADO Repo → ADO Pipeline/Release to VM → Windows Task Scheduler

**SQL/SP path (fallback):** same start → point SQL at Silver → commit to ADO
Repo → manual deploy to VM SQL Server (admin login) → ADF

## Next step

Request Sandbox read/write access from IT, framed around collaboration
efficiency / version control / CI, not dbt specifically (dbt can be
mentioned if asked, not hidden). See conversation history for the reasoning
on why this framing was chosen over a dbt-first pitch.

---

## Usage analysis — Silver/Gold cleanup candidates

**Status: DRAFT, based on automated cross-reference only — NOT verified
against real usage. Do not act on this without confirming the TBD items
below.**

Source files compared:
- `sql_db/DWH_/Database/data_lineage_table.html` (47 Silver tables, 28 Gold
  views, internal SP/Gold/Bronze dependency graph, regenerated 2026-09-01)
- `sql_db/DWH_/Database/powerbi_lineage.md` (16 Power BI reports and what
  Gold/Silver objects they read — manually maintained, several entries still
  marked `TBD`)

Method: cross-referenced which Silver tables / Gold views are reachable from
an actual Power BI report, either directly or via a Gold view that a report
uses.

### ⚠️ TO CONFIRM before treating anything as "safe to remove"

- [ ] **Is Power BI really the only consumer?** Found at least one other
  consumption path not covered by `powerbi_lineage.md`: the `[copilot]`
  schema views (Copilot Agent Knowledge Base layer, see `/copilot-kb` skill).
  There may be others (ad-hoc Excel/SSMS queries, other tools) — needs
  confirming with the team, not just these two documents.
- [ ] **`powerbi_lineage.md` has incomplete entries.** "Montly Membership
  Report" and "Portfolio Dashboard" (among others) have GOLD/SILVER marked
  `TBD` or `--`. Any table only reachable through those reports cannot be
  classified as unused — it's classified as "unknown."
- [ ] **Name mismatch: `Claim_Val`.** `powerbi_lineage.md` lists `Claim_Val`
  as the Gold view for "Deceased Members on Active Memberships," but no Gold
  view named `Claim_Val` exists in `data_lineage_table.html`'s 28 views.
  Either a rename, a typo, or the lineage HTML is missing this object —
  needs checking against the actual database.
- [ ] **`glossary_full_cleaned` / `vw_glossary_hierarchy` naming format
  differs** between the two source docs (`GOV.glossary_full_cleaned` vs
  `glossary_full_cleaned [GOV]`) — likely the same object, treat as matched,
  but worth a sanity check.
- [ ] Observability tables (`ETL_SchemaDrift`, `ETL_SchemaSnapshot`,
  `ETL_VolumeLog`) and `glossary_full_cleaned` show up as "no references"
  in the automated pass purely because they're not report-facing — they are
  in active use for monitoring/governance and should NOT be treated as
  cleanup candidates.

### Gold Views (28 total)

**Directly used by Power BI (15) — confirmed in use:**
Claim_Aggr, Qualtrics_NPS_Score, vw_Agreement_Renewals, vw_Calculated_Deficit,
vw_HCS_Claims, vw_Member_Comms_Detail, vw_Member_Notes,
vw_Member_Payment_Arrears, vw_Membership_Retention_Rate,
vw_Payment_Channel_By_Month, vw_Payment_Channel_Latest, vw_Provider_Reference,
vw_RebateLineCheck, vw_RebateRegistrations,
vw_calculated_deficit_amb_levies_output

**Not found in Power BI list (13) — needs manual confirmation, not
automatically "unused":**
ME_Membership_Joins, ME_Membership_Terminations, ME_Total_Membership,
Membership_Budget, Membership_Movement, Membership_Product_Type,
Membership_Reporting, [copilot].ME_Total_Membership (excluded — Copilot
consumer, see above), vw_Claim_Benefit_Summary, vw_Membership_Current,
vw_RebateReminders, vw_glossary_hierarchy [GOV] (likely matched, see naming
note above), vw_ovhc

### Silver Tables (47 total)

**(A) Directly used by Power BI (11):**
Arrears_Report, Claim_Line_Detail, Deceased_Active_Membership,
Declined_Hicaps_Claim, Earned_Contributions, Member_Daily_Movement, Product,
QMS_Recording_Detail, RebateReminders, Retained_Member, Retention_Tasklist

**(B) Read by a Gold view that IS used by Power BI (12):**
AgentAgreementStatus, CD_AL_Cover_Group_Keys, ClaimDetailsAtService_optimised,
Claim_Fact, Episode_Classification, Episode_Condition_Group,
Member_Comms_Detail, Member_Notes, Member_Payment_Arrears,
Membership_Group_Key, NPS_Score, Payment_Channel

**(C) Read by a Gold view NOT in the Power BI list (3) — depends on
resolving those Gold views above:**
Membership_Budget, Membership_History, Termination_Code

**(D) Not read by any Gold view, but feeds another Silver table via SP (9)
— intermediate/dependency tables, NOT cleanup candidates:**
Claim_Detail_Gen_And_Hosp, Claim_Episode_Staging, Claims_By_Channel,
Current_Product_Fee, Episode_Detail, ICD_Code_Mapping,
Latest_Promo_Sales_Channel_Operator, Member_Products, Previous_Fund

**(E) No Gold reference, no Silver-to-Silver dependency found — genuine
cleanup candidates pending manual confirmation (8, after excluding
observability/governance tables noted above):**
Agent_Monthly_Snapshot, Ancillary_Lookup, Dental_Financial_Detail,
Hospital_Lookup, Latest_Promo_Sales_Channel_By_Person, Product_Premium,
Provider_Claim, RPA_Consolidated

### Next step for this analysis

Before treating category (E) as safe to migrate-skip or archive: confirm
with business/report owners that none of these are used outside Power BI,
resolve the `Claim_Val` naming question, and fill in the `TBD` entries in
`powerbi_lineage.md`. Keep source code for anything excluded from the POC
scope rather than deleting — same caution as for the tables themselves.
