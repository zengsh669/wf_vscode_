---
name: lineage
description: Update the data warehouse lineage diagram (Gold Views, Silver Tables, Silver SPs)
argument-hint: "[add/remove/update/hcs_claims/full] [object details]"
---

# Data Lineage Management Skill

**语言要求（强制）：与用户的所有沟通必须使用简体中文。禁止使用韩文、日文或其他语言。**

You are helping manage the data warehouse lineage diagram.

## Key Files

| File | Purpose |
|------|---------|
| `sql_db/DWH_/Database/data_lineage.html` | The lineage visualization (Mermaid.js flow diagram) |
| `sql_db/DWH_/Database/data_lineage_table.html` | The lineage as an HTML table ("Data Warehouse Lineage Table - Full") |
| `sql_db/DWH_/Database/gold_view.ipynb` | Gold Views definitions |
| `sql_db/DWH_/Database/silver_tbl_sp.ipynb` | Silver Tables & SPs definitions |

## Architecture

```
Gold Views ──reads──> Silver Tables <──loads── Silver SPs <──reads── Bronze Tables
     │                                                              ↑
     └──────────────────── (direct access) ─────────────────────────┘
```

<!-- COMMENTED OUT: This object list is a manual snapshot and will always go stale.
All object counts and dependencies must be derived live from gold_view.ipynb and silver_tbl_sp.ipynb.
Do NOT use this list as source of truth. Kept here for reference only.

## Current Objects (as of 2026-06-29)

### Gold Views (21)

**dbo schema (17):**
- Claim_Aggr → Silver: Claim_Fact
- ME_Membership_Joins → Silver: Membership_Group_Key, Product
- ME_Membership_Terminations → Silver: Membership_Group_Key, Membership_History, Product, Termination_Code
- ME_Total_Membership → Silver: Membership_Group_Key, Product
- Membership_Budget → Silver: Membership_Budget, Product
- Membership_Movement → Silver: Membership_Group_Key, Product
- Membership_Product_Type → Silver: Membership_Group_Key
- Membership_Reporting → Silver: Membership_Group_Key, Membership_History, Product, Termination_Code (+ Bronze direct: group_key_full_by_branch)
- vw_Calculated_Deficit → Silver: ClaimDetailsAtService_optimised (+ Bronze direct: claim_generalitem, claim_hospitalitem, claim_line, group_key_full_by_branch, memship, person)
- vw_calculated_deficit_amb_levies_output → Silver: CD_AL_Cover_Group_Keys
- vw_Claim_Benefit_Summary → Silver: Claim_Line_Detail
- vw_HCS_Claims → Silver: ClaimDetailsAtService_optimised, Episode_Classification, Episode_Condition_Group (+ Bronze direct: claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, cover_type, fund_classification, item, item_group, memship, person, person_membership, PersonAddressHomePostal, provider, provider_number, provider_type, service_type)
- vw_Membership_Current → (Direct Bronze only: cover, cover_product, grouping, memship, memship_20260529, operator, person_membership, product, promotion, promotion_reference, promotion_sales_channel)
- vw_ovhc → (Direct Bronze only: country_code, cover, cover_product, grouping, memship, memship_app_agent, memship_app_dep, memship_app_sales_promo, product, promotion_sales_channel, visa_type)
- vw_RebateLineCheck → (Direct Bronze only: in_rebate, MemberRebate, memship, person, person_membership, PersonContact)
- vw_RebateRegistrations → (Direct Bronze only: hic_rebate_error, hic_rebate_segment, hic_rebate_segment_error, MemberRebate, memship, rebate_reg_errors)
- vw_RebateReminders → (Direct Bronze only: MemberBranch, MemberCover, MemberRebate, memship, person, person_membership, PersonAddressHomePostal, PersonContact, rebate, rebate_form_flag, web_security)

**GOV schema (1):**
- vw_glossary_hierarchy → Silver: GOV.glossary_full_cleaned

**copilot schema (3) — wrapper views over dbo equivalents:**
- copilot.ME_Total_Membership → (via dbo.ME_Total_Membership)
- copilot.Membership_Budget → (via dbo.Membership_Budget)
- copilot.vw_ovhc → (via dbo.vw_ovhc)

### Silver Tables (40) with corresponding SPs and Bronze Sources

**HCS Claims Pipeline:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| ICD_Code_Mapping | usp_Load_ICD_Mapping | - | icd_type |
| Claim_Episode_Staging | sp_LoadFactClaimData | - | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, payee |
| Claim_Detail_Gen_And_Hosp | usp_Load_Claim_Detail_Gen_And_Hosp | - | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, payee |
| ClaimDetailsAtService_optimised | usp_Create_ClaimDetailsAtService_Optimised | - | claim_line, cover, cover_product, grouping, membership_group, person, plan_detail, product |
| Episode_Detail | usp_Load_Episode_Base_Data | Claim_Episode_Staging, ICD_Code_Mapping | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, episode, episode_diagnosis_procedure, medical_item_icd_10am |
| Episode_Classification | usp_Process_Episode_Classification | Episode_Detail | icd10_category_map, icd10_d_category_map, icd10_h_category_map, icd10_q_category_map, icd10_r_category_map, icd10_s_category_map, icd10_t_category_map, icd10_z_category_map |
| Episode_Condition_Group | usp_generate_episode_condition_group | Episode_Classification | - |

**Claims & Lookups:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| Claim_Fact | Load_Claim_Fact | - | claim_generalitem, claim_hospitalitem, claim_line, cover, cover_product, person, product, provider, provider_number |
| Claim_Line_Detail | usp_Load_Claim_Line_Detail | Claim_Detail_Gen_And_Hosp, ClaimDetailsAtService_optimised, Claims_By_Channel, Latest_Promo_Sales_Channel_Operator, Previous_Fund | claim_generalitem, claim_hospitalitem, claim_line, contract_details, contract_item, cover_type, eligibility_illness_code, eligibility_illness_code_item, fund_classification, grouping, item, item_averagefee, item_group, manual_benefit_reason, MemberAgent, MemberCover, memship, person, product, provider, provider_group, provider_number, provider_type, providernumber_contract, service_type, web_security |
| Claims_By_Channel | usp_Load_Claims_By_Channel | - | claim, claim_line, claim_status |
| Ancillary_Lookup | usp_Load_Ancillary_Lookup | Product | claim_line, cover, cover_product |
| Hospital_Lookup | usp_Load_Hospital_Lookup | Product | claim_line, cover, cover_product |
| Declined_Hicaps_Claim | usp_Load_Declined_Hicaps_Claim | ClaimDetailsAtService_optimised | claim_generalitem, claim_line, grouping, MemberCover, note, sub_ref_type |
| CD_AL_Cover_Group_Keys | usp_load_calculated_deficit_amb_levies | - | group_key_full_by_branch |

**Membership & Product:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| Membership_Group_Key | Membership_Group_Key_Load | - | group_key_full_by_branch, Membership_Channel_Map, Membership_Fund_Map |
| Membership_History | Membership_History_Load | - | Membership_Fund_Map, person_, person_20260529, person_membership_ |
| Membership_Budget | Membership_Budget_Load | - | Membership_Channel_Budget, Membership_Product_Budget, Membership_Product_Map |
| Product | Product_Load | - | Membership_Product_Map, product |
| Member_Products | usp_Load_Member_Products | Current_Product_Fee | cover, cover_product, product |
| Product_Premium | usp_Load_Product_Premium | Member_Products | - |
| Current_Product_Fee | usp_Load_Current_Product_Fee | - | product_fee |
| Latest_Promo_Sales_Channel_By_Person | usp_Load_Latest_Promo_Sales_Channel_By_Person | - | memship, operator, person_membership, promotion, promotion_reference, promotion_sales_channel |
| Latest_Promo_Sales_Channel_Operator | usp_Load_Latest_Promo_Sales_Channel_Operator | - | operator, person_membership, promotion, promotion_reference, promotion_sales_channel |

**Financials:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| Earned_Contributions | usp_Load_Earned_Contributions | - | cover, cover_product, group_key_full_by_branch, grouping, memship, memship_app_agent, product, product_fee, receipt, receipt_status |
| Provider_Claim | usp_Load_provider_claim | - | billing_agent, payment, person, provider_claim, provider_claim_eclipse, provider_claim_line |
| AgentAgreementStatus | LoadAgentAgreementStatus | - | grouping |

**Retention & Member Admin:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| Retained_Member | usp_Load_Retained_Member | - | cover, cover_product, MemberBranch, MemberCover, memship, note, operator, person_membership, PersonContact, product, product_fee, promotion, promotion_reference, promotion_sales_channel, sub_ref_type |
| Retention_Tasklist | usp_Load_Retention_Tasklist | - | grouping, memship, memship_status, memship_tasklist |
| Deceased_Active_Membership | usp_Deceased_Active_Membership | - | MemberGroup, memship, person, person_membership, security_level |
| RebateReminders | Load_RebateReminders | - | MemberBranch, MemberCover, MemberRebate, memship, person, person_membership, PersonAddressHomePostal, PersonContact, rebate, rebate_form_flag, web_security |
| Arrears_Report | Load_ArrearsReportPayroll | - | billing_group, billing_type, grouping, MemberAgent, MemberBranch, MemberCover, MemberGroup, memship, person, person_membership, security_level, web_security |
| Previous_Fund | usp_Load_Previous_Fund | - | memship, person_membership, person_previous_fund, previous_fund |

**Reference & Lookup:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| Termination_Code | Termination_Code_Load | - | Membership_Termination_Map, termination_code |
| QMS_Recording_Detail | usp_Load_QMS_Recording_Detail | - | Flag_Details [qms], Recording_Details [qms], User_Details [qms] |
| RPA_Consolidated | usp_Load_RPA_Consolidated | - | claim_status, claim_status_type, item_averagefee, rpa |

**Observability (obs schema) — single SP writes all 3 tables:**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| ETL_VolumeLog [obs] | usp_CheckHealth [obs] | - | INFORMATION_SCHEMA.TABLES (dbo/GOV) |
| ETL_SchemaDrift [obs] | usp_CheckHealth [obs] | ETL_SchemaSnapshot [obs] | INFORMATION_SCHEMA.COLUMNS (dbo/GOV) |
| ETL_SchemaSnapshot [obs] | usp_CheckHealth [obs] | - | INFORMATION_SCHEMA.COLUMNS (dbo/GOV) |

**Governance (GOV schema):**
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| GOV.glossary_cleaned | usp_Load_GOV_Glossary_Cleaned | - | Westfund_Enterprise_Glossary |
| GOV.glossary_full_cleaned | usp_Load_GOV_Glossary_Full_Cleaned | - | Westfund_Enterprise_Glossary |

-->

## Task Instructions

**CRITICAL RULE: Always read actual SQL from notebooks first — SKILL.md object lists must never be used as source of truth.**
Before executing ANY lineage operation (add/remove/update/regenerate/full), you MUST parse `gold_view.ipynb` and `silver_tbl_sp.ipynb` live to derive all object names, counts, dependencies, and Bronze sources. The commented-out object list in this SKILL.md is a stale snapshot kept for human reference only — do NOT use it to answer any question about what objects exist or what their dependencies are. Every answer must come from the notebooks.

**CRITICAL RULE: Object classification priority.**
When classifying a notebook object as Table vs SP, always apply this priority order:
1. If SQL contains `CREATE PROCEDURE` or `CREATE PROC` → **SP** (even if the SP body also contains `CREATE TABLE` for temp tables)
2. If SQL contains `CREATE VIEW` → **Gold View**
3. If SQL contains `CREATE TABLE` (and no `CREATE PROCEDURE`) → **Silver Table**
Never use `CREATE TABLE` alone to classify an object as a Table when `CREATE PROCEDURE` is also present in the same SQL block.

**CRITICAL RULE: A single notebook cell header may contain multiple CREATE VIEW blocks.**
In `gold_view.ipynb`, one markdown header (e.g. `# [dbo].[ME_Total_Membership]`) may be followed by code cells containing both `[dbo].[ViewName]` AND `[copilot].[ViewName]`. Always split on `CREATE VIEW` boundaries before parsing dependencies — never treat the entire cell block as a single view.

**CRITICAL RULE: Strip SQL comments before parsing dependencies.**
Before extracting Bronze/Silver table references from any SQL block, always remove:
1. Line comments: `--` to end of line
2. Block comments: `/* ... */`
Failure to strip comments causes commented-out table references (e.g. old JOIN code left as `-- LEFT JOIN BRONZE.dbo.OldTable`) to appear as active dependencies. Always apply comment stripping FIRST, then run the regex against the cleaned SQL.

**CRITICAL RULE: Object references use bracket notation — regex must handle it.**
SQL in these notebooks uses both `dbo.TableName` and `[SILVER].[dbo].[TableName]` and `SILVER.dbo.[TableName]` formats. Regex patterns that only match `SILVER\.dbo\.(\w+)` will silently miss references written as `[SILVER].[dbo].[TableName]`. Always write patterns that tolerate optional brackets: `\[?SILVER\]?\.\[?dbo\]?\.\[?(\w+)\]?`.

**CRITICAL RULE: Silver dependency regex must match any schema, not just `dbo`.**
Some Gold Views and SPs reference Silver tables in non-dbo schemas, e.g. `SILVER.GOV.glossary_full_cleaned`. A regex that only matches `SILVER.dbo.X` will silently miss these. Always use a pattern that matches any schema: `\[?SILVER\]?\.\[?\w+\]?\.\[?(\w+)\]?`.

**CRITICAL RULE: Derive Table→SP mapping from SP SQL, never by name matching.**
Do NOT guess which SP loads which table by matching names (e.g. assuming `usp_Load_X` loads table `X`). The only correct method is:
1. Parse each SP's SQL (after stripping comments)
2. Find ALL `TRUNCATE TABLE`, `INSERT INTO`, and `DROP TABLE` statements — these identify the actual target table(s)
3. Use those targets to build the Table→SP mapping

This is required because naming conventions are inconsistent — for example:
- `usp_load_calculated_deficit_amb_levies` loads `CD_AL_Cover_Group_Keys` (not `calculated_deficit_amb_levies`)
- `sp_LoadFactClaimData` loads `Claim_Episode_Staging` (not `fact_claim_data`)

**CRITICAL RULE: Some SPs use DROP TABLE + SELECT INTO instead of TRUNCATE + INSERT.**
Not all SPs follow the standard TRUNCATE + INSERT pattern. Some use `DROP TABLE ... CREATE TABLE ... INSERT INTO` or even `DROP TABLE` alone to identify the target. Include `DROP TABLE` in your target-extraction regex, but exclude temp tables (names starting with `#`).

**CRITICAL RULE: Some SPs write to MULTIPLE target tables — extract ALL INSERT INTO targets, not just the first.**
`obs.usp_CheckHealth` writes to three separate tables (`ETL_VolumeLog`, `ETL_SchemaDrift`, `ETL_SchemaSnapshot`) in a single SP using `DELETE + INSERT` instead of `TRUNCATE + INSERT`. A regex that stops at the first `INSERT INTO` match will silently drop all subsequent targets. Always collect ALL non-temp-table `INSERT INTO` targets from each SP, and emit one lineage row per target table. Also: `DELETE FROM` (not `TRUNCATE`) is a valid refresh pattern — do not require `TRUNCATE` as a signal that a table is being loaded.

**CRITICAL RULE: Gold View count must include ALL schemas — copilot views are real Gold Views.**
`copilot` schema views (e.g. `[copilot].[ME_Total_Membership]`) are real `CREATE VIEW` objects deployed to the database and must be counted in the Gold View total. Do NOT exclude them from the subtitle count on the grounds that they "wrap" a dbo view. The subtitle number must equal the total `CREATE VIEW` count across ALL schemas in `gold_view.ipynb`.

**CRITICAL RULE: Object counts in the subtitle must be computed from notebooks, never copied from the existing HTML.**
After parsing all objects, count Gold Views, Silver Tables, and Silver SPs programmatically and write those numbers into the subtitle line. Do NOT reuse whatever numbers were already in the HTML file — they may be stale.

When user invokes `/lineage`, follow these steps:

1. **If user wants to add/remove/update objects:**
   - **Read the actual SQL from `gold_view.ipynb` / `silver_tbl_sp.ipynb`** for the affected objects
   - Parse Bronze sources and Silver dependencies from the SQL (FROM clauses, JOINs)
   - Read the current `data_lineage.html`
   - Modify the Mermaid diagram accordingly
   - Update the statistics numbers (recount from notebooks — do NOT copy existing numbers)

2. **If user wants to regenerate from notebooks:**
   - Extract objects from `gold_view.ipynb` and `silver_tbl_sp.ipynb`
   - Analyze SQL to find dependencies (FROM SILVER.dbo.XXX and FROM BRONZE.dbo.XXX)
   - **IMPORTANT: Always update BOTH HTML files:**
     - `data_lineage.html` — Mermaid.js flow diagram
     - `data_lineage_table.html` — HTML table view

3. **If user specifies `hcs_claims` filter:**
   - Generate a filtered lineage showing ONLY these 6 SPs and their dependencies:
     - usp_Create_ClaimDetailsAtService_Optimised
     - sp_LoadFactClaimData
     - usp_Load_ICD_Mapping
     - usp_Load_Episode_Base_Data
     - usp_Process_Episode_Classification
     - usp_generate_episode_condition_group
   - Related Silver Tables: ClaimDetailsAtService_optimised, Claim_Episode_Staging, ICD_Code_Mapping, Episode_Detail, Episode_Classification, Episode_Condition_Group
   - Related Gold View: vw_HCS_Claims
   - Bronze Tables: Only those used by the 6 SPs

4. **If user specifies `full` option:**
   - Restore the complete lineage diagram with all objects
   - Always recount from notebooks — never hardcode these numbers

5. **IMPORTANT: Always show updated table at the end of conversation:**
   - After any lineage operation (add/remove/update/regenerate), display the updated "Silver Tables with SPs and Bronze Sources" table in the chat
   - This helps user verify the changes immediately

6. **HTML Structure Reference:**
   ```
   G# = Gold View node
   S# = Silver Table node
   SP# = Stored Procedure node
   B# = Bronze Table node

   G# --> S#      (solid = View reads Table)
   S# -.-> SP#    (dashed = SP loads Table)
   SP# -.-> B#    (dashed = SP reads Bronze)
   G# -.-> B#     (dashed = View directly reads Bronze)

   Colors:
   - Gold: #ffd700
   - Silver: #c0c0c0
   - SP: #4ecdc4
   - Bronze: #cd7f32
   - Direct Bronze View: #ffa500 (orange)
   ```

## Example Usage

```
/lineage add Silver table "NewTable" with SP "Load_NewTable"
/lineage remove Silver table "OldTable"
/lineage update - Gold View "vw_HCS_Claims" now also reads "NewTable"
/lineage regenerate from notebooks
/lineage hcs_claims              # Show only 6 HCS Claims SPs lineage
/lineage full                    # Restore complete lineage (all 38 SPs)
```

## HCS Claims Filter Details

When `hcs_claims` option is used, show only these objects:

| SP | Silver Table (Target) | Silver Inputs | Bronze Sources |
|----|----------------------|---------------|----------------|
| usp_Load_ICD_Mapping | ICD_Code_Mapping | - | icd_type |
| sp_LoadFactClaimData | Claim_Episode_Staging | - | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, payee |
| usp_Create_ClaimDetailsAtService_Optimised | ClaimDetailsAtService_optimised | - | claim_line, cover, cover_product, grouping, membership_group, person, plan_detail, product |
| usp_Load_Episode_Base_Data | Episode_Detail | Claim_Episode_Staging, ICD_Code_Mapping | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, episode, episode_diagnosis_procedure, medical_item_icd_10am |
| usp_Process_Episode_Classification | Episode_Classification | Episode_Detail | icd10_category_map, icd10_d_category_map, icd10_h_category_map, icd10_q_category_map, icd10_r_category_map, icd10_s_category_map, icd10_t_category_map, icd10_z_category_map |
| usp_generate_episode_condition_group | Episode_Condition_Group | Episode_Classification | - |

**Related Gold View:** vw_HCS_Claims (reads ClaimDetailsAtService_optimised, Episode_Classification, Episode_Condition_Group)

## Output Format

After completing any lineage operation, always display the updated table:

```
## Updated Table Structure

| Table | SP | Bronze Sources |
|-------|-----|----------------|
| AgentAgreementStatus | LoadAgentAgreementStatus | grouping |
| ... | ... | ... |
```
