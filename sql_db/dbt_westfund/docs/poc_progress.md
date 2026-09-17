# dbt POC — Progress Notes

Last updated: 2026-09-17

## Goal

Evaluate dbt (dbt-core + dbt-sqlserver) as a replacement for SP-driven Silver
table loads, primarily to solve manual dependency ordering in ADF. Secondary
goal: auto-generated lineage. Scope narrows to only the Silver tables / Gold
views that are actually used, using this migration as a cleanup opportunity.

## Status: admin connection to Sandbox verified (2026-09-17)

Got an admin account (`shaun.adm`) from IT for SQL05 (the server hosting
BRONZE/SILVER/GOLD/SANDBOX). `dbt debug` now connects successfully as
`shaun.adm` against SANDBOX, and CREATE TABLE / INSERT / CREATE PROCEDURE /
EXEC all tested successfully under that account. See "Multi-account /
multi-machine setup notes" below for the connection troubleshooting details
and what still needs replicating for a real VM deployment.

## Local environment — DONE

- Python 3.14, dbt-core 1.12.3, dbt-sqlserver 1.11.1 installed in
  `sql_db/dbt_westfund/.venv/`
- ODBC Driver 17 for SQL Server already present, no install needed
- Project scaffold created: `dbt_project.yml`, `models/sandbox/` (empty),
  `profiles.yml.example`
- `~/.dbt/profiles.yml` configured; `dbt debug` now passes fully under the
  `shaun.adm` admin account (see notes below)
- Committed and pushed to GitHub (`wf_vscode_`)

## Multi-account / multi-machine setup notes

Two things that are NOT obvious and will need repeating for VM deployment:

1. **`profiles.yml` belongs to the Windows account, not the project.**
   dbt reads it from `C:\Users\<account>\.dbt\profiles.yml`. Since Windows
   Authentication (`authentication: ActiveDirectoryIntegrated`) always uses
   whoever is currently logged into that session, `zengsh` and `shaun.adm`
   each need their own copy at their own path — copying the file isn't
   enough on its own, each account's `.dbt` folder has to actually contain
   one. Confirmed by running `dbt debug` as `shaun.adm` and getting
   "profiles.yml file [ERROR not found]" until a copy was placed at
   `C:\Users\shaun.adm\.dbt\profiles.yml`.
2. **The server address matters more than expected.** `server: rpsqlrp01`
   (short hostname) causes `dbt debug` to fail with `SSL Provider: The
   target principal name is incorrect` — a Kerberos/SPN mismatch, not a
   permissions issue. Switching to the FQDN `prdsql05.westfund.com.au`
   (the same address used successfully in the SSMS/mssql extension
   connection dialog) fixed it immediately. All three `profiles.yml`
   copies (`zengsh`, `shaun.adm`, and the `profiles.yml.example` template)
   now use the FQDN.
3. **`.venv` cannot be copied between machines/accounts.** It has to be
   rebuilt (`py -m venv .venv` + `pip install dbt-core dbt-sqlserver`) at
   the new location — this will apply again when setting up the VM.
4. **VM's `profiles.yml` will need real changes, not just a copy**: target
   should point at `silver` (not `sandbox`), and the authentication method
   for an unattended Task Scheduler job needs separate thought — Windows
   Authentication as used here depends on an interactively logged-in
   session, which won't exist when Task Scheduler triggers the job
   unattended.

## VM deployment checklist (not started — reference for when this stage begins)

None of this is done yet. Listed here so it isn't re-derived from scratch
later. VM setup mirrors the local setup steps above, but nothing gets
copied across — each piece is reinstalled/reconfigured fresh on the VM:

- [ ] Install Python on the VM (version compatible with dbt-sqlserver;
      doesn't need to match the local 3.14 exactly)
- [ ] Confirm ODBC Driver 17 (or 18) for SQL Server is present on the VM
      (likely already there if the VM talks to SQL Server for anything else)
- [ ] Build a fresh `.venv` on the VM: `python -m venv .venv` then
      `pip install dbt-core dbt-sqlserver`
- [ ] Deploy the project code (`models/`, `dbt_project.yml`, etc. — i.e.
      whatever is git-tracked, since `.gitignore` already excludes
      `.venv/`, `target/`, `dbt_packages/`, `logs/`) via the ADO Pipeline
      from the ADO Repo, not manual copy
- [ ] Write a VM-specific `profiles.yml` at
      `C:\Users\<execution-account>\.dbt\profiles.yml` — NOT a copy of the
      local one:
      - `target: silver` (not `sandbox`)
      - `database: SILVER`
      - authentication method needs separate thought: Windows
        Authentication (`ActiveDirectoryIntegrated`) depends on an
        interactive login session, which won't exist when Task Scheduler
        triggers the job unattended — need to confirm with IT how the
        execution account authenticates non-interactively
      - use the FQDN `prdsql05.westfund.com.au` for `server`, not the short
        hostname (see setup notes above — short hostname causes a
        Kerberos/SPN failure)
- [ ] Write a `.bat` script that `cd`s into the project folder and runs
      `.venv\Scripts\dbt.exe run` (and optionally `dbt test`)
- [ ] Manually run the `.bat` once to confirm it works before automating it
- [ ] Set up Windows Task Scheduler to trigger the `.bat` on a schedule,
      running as the correct execution account
- [ ] Decide on failure handling — Task Scheduler doesn't alert on failure
      the way ADF does; need the `.bat` (or a wrapper script) to check
      `dbt run`'s exit code / `target/run_results.json` and send an email
      or log a failure somewhere visible
- [ ] If any dbt packages get added later (e.g. `dbt_utils`, via
      `packages.yml`), add a `dbt deps` step before `dbt run` — the
      `dbt_packages/` folder isn't git-tracked, so it won't arrive with the
      code deploy and has to be pulled fresh on the VM too. Not applicable
      yet — no packages in use as of this writing.
- [ ] `dbt debug` currently reports "git [ERROR]" under the `shaun.adm`
      account (git isn't installed / not on PATH for that account). This
      doesn't block `dbt run` or `dbt test` — only matters if `dbt deps`
      ever needs to pull a package directly from a git URL. Install git for
      the VM's execution account only if that need actually comes up.

## Planned deployment paths (not yet submitted to IT)

**Python/dbt path:** Sandbox dev/test → Jira ticket → point config at Silver
→ commit to ADO Repo → ADO Pipeline/Release to VM → Windows Task Scheduler

**SQL/SP path (fallback):** same start → point SQL at Silver → commit to ADO
Repo → manual deploy to VM SQL Server (admin login) → ADF

## Next step

Write the first real dbt model against SANDBOX using the admin VSCode
window, and verify its output against the existing Silver table it's meant
to replicate (using `Lib_Westfund`'s `compare_content`). Separately, VM
deployment (see setup notes above) remains its own follow-on task once a
model or two has been validated in Sandbox.

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
