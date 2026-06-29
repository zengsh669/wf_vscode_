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

## Current Objects (as of 2026-04-02)

### Gold Views (17)
- Claim_Aggr -> Claim_Fact
- ME_Membership_Joins -> Membership_Group_Key, Product
- ME_Membership_Terminations -> Membership_Group_Key, Product, Membership_History, Termination_Code
- ME_Total_Membership -> Membership_Group_Key, Product
- Membership_Budget -> Membership_Budget, Product
- Membership_Movement -> Membership_Group_Key, Product
- Membership_Product_Type -> Membership_Group_Key
- Membership_Reporting -> Membership_Group_Key, Product, Membership_History, Termination_Code (+ Bronze direct: group_key_full_by_branch)
- vw_Calculated_Deficit -> ClaimDetailsAtService_optimised (+ Bronze: group_key_full_by_branch, claim_line, claim_hospitalitem, claim_generalitem, person, memship)
- vw_calculated_deficit_amb_levies_output -> calculated_deficit_amb_levies
- vw_HCS_Claims -> ClaimDetailsAtService_optimised, episode_classification, episode_condition_group (+ Bronze direct: 18 tables incl. ClaimDetailGenAndHosp, ClaimDetailsAtService, PersonAddressHomePostal, claim_line_status_type, cover_type, fund_classification, item, item_group, memship, person, person_membership, provider, provider_number, provider_type, service_type, etc.)
- vw_Membership_Current -> (Direct Bronze: memship, memship_20260331, cover, cover_product, promotion_reference, person_membership, product, promotion, promotion_sales_channel, operator, grouping)
- vw_ovhc -> (Direct Bronze: cover_product, product, cover, memship, memship_app_dep, memship_app_agent, memship_app_sales_promo, promotion_sales_channel, country_code, visa_type, grouping)
- vw_RebateLineCheck -> (Direct Bronze: memship, MemberRebate, person_membership, person, PersonContact, in_rebate)
- vw_RebateRegistrations -> (Direct Bronze: MemberRebate, hic_rebate_error, hic_rebate_segment, hic_rebate_segment_error, memship, rebate_reg_errors)
- vw_RebateReminders -> (Direct Bronze ONLY: MemberBranch, MemberCover, MemberRebate, PersonAddressHomePostal, PersonContact, memship, person, person_membership, rebate, rebate_form_flag, web_security)
- vw_glossary_hierarchy [GOV schema] -> GOV.glossary_full_cleaned

### Silver Tables (29) with corresponding SPs and Bronze Sources
| Table | SP | Silver Inputs | Bronze Sources |
|-------|-----|---------------|----------------|
| AgentAgreementStatus | LoadAgentAgreementStatus | - | grouping |
| Ancillary_Lookup | usp_Load_Ancillary_Lookup | - | claim_line, cover, cover_product |
| ArrearsReport | Load_ArrearsReportPayroll | - | MemberAgent, MemberBranch, MemberCover, MemberGroup, billing_group, billing_type, grouping, memship, person, person_membership, security_level, web_security |
| calculated_deficit_amb_levies | usp_load_calculated_deficit_amb_levies | - | group_key_full_by_branch |
| Claim_Fact | Load_Claim_Fact | - | claim_generalitem, claim_hospitalitem, claim_line, cover, cover_product, person, product, provider, provider_number |
| ClaimDetailsAtService_optimised | usp_Create_ClaimDetailsAtService_Optimised | - | claim_line, cover, cover_product, grouping, membership_group, person, plan_detail, product |
| Current_Product_Fee | usp_Load_Current_Product_Fee | - | product_fee |
| Deceased_Active_Membership | usp_Deceased_Active_Membership | - | MemberGroup, memship, person, person_membership, security_level |
| Earned_Contributions | usp_Load_Earned_Contributions | - | cover, cover_product, group_key_full_by_branch, grouping, memship, memship_app_agent, product, product_fee, receipt, receipt_status |
| episode_classification | usp_Process_Episode_Classification | etl_episode_work | icd10_category_map, icd10_d/h/q/r/s/t/z_category_map |
| episode_condition_group | usp_generate_episode_condition_group | episode_classification | - |
| etl_episode_work | usp_Load_Episode_Base_Data | etl_icd_mapping, fact_claim_data | ClaimDetailGenAndHosp, claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, episode, episode_diagnosis_procedure, medical_item_icd_10am |
| etl_icd_mapping | usp_Load_ICD_Mapping | - | icd_type |
| fact_claim_data | sp_LoadFactClaimData | - | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, payee |
| Hospital_Lookup | usp_Load_Hospital_Lookup | - | claim_line, cover, cover_product |
| Latest_Promo_Sales_Channel_By_Person | usp_Load_Latest_Promo_Sales_Channel_By_Person | - | memship, operator, person_membership, promotion, promotion_reference, promotion_sales_channel |
| Member_Products | usp_Load_Member_Products | Current_Product_Fee | cover, cover_product, product |
| Membership_Budget | Membership_Budget_Load | - | Membership_Channel_Budget, Membership_Product_Budget, Membership_Product_Map |
| Membership_Group_Key | Membership_Group_Key_Load | - | Membership_Channel_Map, Membership_Fund_Map, group_key_full_by_branch |
| Membership_History | Membership_History_Load | - | Membership_Fund_Map, person_20260331, person_, person_membership_ |
| Product | Product_Load | - | Membership_Product_Map, product |
| Product_Premium | usp_Load_Product_Premium | Member_Products | - |
| provider_claim | usp_Load_provider_claim | - | billing_agent, payment, person, provider_claim, provider_claim_eclipse, provider_claim_line |
| RebateReminders | Load_RebateReminders | - | MemberBranch, MemberCover, MemberRebate, PersonAddressHomePostal, PersonContact, memship, person, person_membership, rebate, rebate_form_flag, web_security |
| Retained_Member | usp_Load_Retained_Member | - | MemberBranch, MemberCover, PersonContact, cover, cover_product, memship, note, operator, person_membership, product, product_fee, promotion, promotion_reference, promotion_sales_channel, sub_ref_type |
| Retention_Tasklist | usp_Load_Retention_Tasklist | - | grouping, memship, memship_status, memship_tasklist |
| Termination_Code | Termination_Code_Load | - | Membership_Termination_Map, termination_code |
| GOV.glossary_cleaned | usp_Load_GOV_Glossary_Cleaned | - | Westfund_Enterprise_Glossary |
| GOV.glossary_full_cleaned | usp_Load_GOV_Glossary_Full_Cleaned | - | Westfund_Enterprise_Glossary |

### Bronze Tables (88) by Category

| Category | Tables |
|----------|--------|
| Claim Tables | ClaimDetailGenAndHosp, ClaimDetailsAtService, claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type |
| Member Tables | MemberAgent, MemberBranch, MemberCover, MemberGroup, MemberRebate, membership_group, memship, person, person_membership |
| Membership Config | Membership_Channel_Budget, Membership_Channel_Map, Membership_Fund_Map, Membership_Product_Budget, Membership_Product_Map, Membership_Termination_Map |
| Person Tables | PersonAddressHomePostal, PersonContact |
| Billing Tables | billing_agent, billing_group, billing_type, payment, payee |
| Cover Tables | cover, cover_product, cover_type, fund_classification, plan_detail, product |
| Episode Tables | episode, episode_diagnosis_procedure, medical_item_icd_10am |
| ICD Mapping | icd10_category_map, icd10_d_category_map, icd10_h_category_map, icd10_q_category_map, icd10_r_category_map, icd10_s_category_map, icd10_t_category_map, icd10_z_category_map, icd_type |
| Rebate Tables | hic_rebate_error, hic_rebate_segment, hic_rebate_segment_error, in_rebate, rebate, rebate_form_flag, rebate_reg_errors |
| Provider Tables | provider, provider_claim, provider_claim_eclipse, provider_claim_line, provider_number, provider_type |
| OVHC Tables | country_code, memship_app_agent, memship_app_dep, memship_app_sales_promo, promotion_sales_channel, visa_type |
| Snapshot Tables | memship_20260331, operator, person_, person_20260331, person_membership_, promotion, promotion_reference |
| Other Tables | group_key_full_by_branch, grouping, item, item_group, security_level, service_type, termination_code, web_security |
| Financial Tables | product_fee, receipt, receipt_status |
| Retention Tables | memship_status, memship_tasklist, note, sub_ref_type |
| GOV Tables | Westfund_Enterprise_Glossary |

## Task Instructions

**CRITICAL RULE: Always read actual SQL from notebooks first.**
Before making ANY update to `data_lineage_table.html` or `data_lineage.html`, you MUST read the actual SQL from `gold_view.ipynb` and/or `silver_tbl_sp.ipynb` for the affected objects. Never rely on the object lists in this SKILL.md as the source of truth for Bronze table names, Silver dependencies, or any SQL-derived detail — those lists are summaries only and can be stale. Derive all dependency information directly from the notebook SQL.

**CRITICAL RULE: Object counts in the subtitle must be computed from notebooks, never copied from the existing HTML.**
After parsing all objects, count Gold Views, Silver Tables, and Silver SPs programmatically and write those numbers into the subtitle line. Do NOT reuse whatever numbers were already in the HTML file — they may be stale.

**CRITICAL RULE: Object classification priority.**
When classifying a notebook object as Table vs SP, always apply this priority order:
1. If SQL contains `CREATE PROCEDURE` or `CREATE PROC` → **SP** (even if the SP body also contains `CREATE TABLE` for temp tables)
2. If SQL contains `CREATE VIEW` → **Gold View**
3. If SQL contains `CREATE TABLE` (and no `CREATE PROCEDURE`) → **Silver Table**
Never use `CREATE TABLE` alone to classify an object as a Table when `CREATE PROCEDURE` is also present in the same SQL block.

**CRITICAL RULE: Strip SQL comments before parsing dependencies.**
Before extracting Bronze/Silver table references from any SQL block, always remove:
1. Line comments: `--` to end of line
2. Block comments: `/* ... */`
Failure to strip comments causes commented-out table references (e.g. old JOIN code left as `-- LEFT JOIN BRONZE.dbo.OldTable`) to appear as active dependencies. Always apply comment stripping FIRST, then run the regex against the cleaned SQL.

**CRITICAL RULE: Derive Table→SP mapping from SP SQL, never by name matching.**
Do NOT guess which SP loads which table by matching names (e.g. assuming `usp_Load_X` loads table `X`). The only correct method is:
1. Parse each SP's SQL (after stripping comments)
2. Find all `TRUNCATE TABLE`, `INSERT INTO`, and `DROP TABLE` statements — these identify the actual target table
3. Use that target to build the Table→SP mapping

This is required because naming conventions are inconsistent — for example:
- `usp_load_calculated_deficit_amb_levies` loads `CD_AL_Cover_Group_Keys` (not `calculated_deficit_amb_levies`)
- `sp_LoadFactClaimData` loads `Claim_Episode_Staging` (not `fact_claim_data`)

**CRITICAL RULE: Object references use bracket notation — regex must handle it.**
SQL in these notebooks uses both `dbo.TableName` and `[SILVER].[dbo].[TableName]` and `SILVER.dbo.[TableName]` formats. Regex patterns that only match `SILVER\.dbo\.(\w+)` will silently miss references written as `[SILVER].[dbo].[TableName]`. Always write patterns that tolerate optional brackets: `\[?SILVER\]?\.\[?dbo\]?\.\[?(\w+)\]?`.

**CRITICAL RULE: Some SPs use DROP TABLE + SELECT INTO instead of TRUNCATE + INSERT.**
Not all SPs follow the standard TRUNCATE + INSERT pattern. Some use `DROP TABLE ... CREATE TABLE ... INSERT INTO` or even `DROP TABLE` alone to identify the target. Include `DROP TABLE` in your target-extraction regex, but exclude temp tables (names starting with `#`).

**CRITICAL RULE: A single notebook cell header may contain multiple CREATE VIEW blocks.**
In `gold_view.ipynb`, one markdown header (e.g. `# [dbo].[ME_Total_Membership]`) may be followed by code cells containing both `[dbo].[ViewName]` AND `[copilot].[ViewName]`. Always split on `CREATE VIEW` boundaries before parsing dependencies — never treat the entire cell block as a single view.

When user invokes `/lineage`, follow these steps:

1. **If user wants to add/remove/update objects:**
   - **Read the actual SQL from `gold_view.ipynb` / `silver_tbl_sp.ipynb`** for the affected objects
   - Parse Bronze sources and Silver dependencies from the SQL (FROM clauses, JOINs)
   - Read the current `data_lineage.html`
   - Modify the Mermaid diagram accordingly
   - Update the statistics numbers
   - Update this SKILL.md file with the new object list

2. **If user wants to regenerate from notebooks:**
   - Extract objects from `gold_view.ipynb` and `silver_tbl_sp.ipynb`
   - Analyze SQL to find dependencies (FROM SILVER.dbo.XXX and FROM BRONZE.dbo.XXX)
   - **IMPORTANT: Always update BOTH HTML files:**
     - `data_lineage.html` — Mermaid.js flow diagram
     - `data_lineage_table.html` — HTML table view
   - Update this SKILL.md with the latest object counts and lists

3. **If user specifies `hcs_claims` filter:**
   - Generate a filtered lineage showing ONLY these 6 SPs and their dependencies:
     - usp_Create_ClaimDetailsAtService_Optimised
     - sp_LoadFactClaimData
     - usp_Load_ICD_Mapping
     - usp_Load_Episode_Base_Data
     - usp_Process_Episode_Classification
     - usp_generate_episode_condition_group
   - Related Silver Tables: ClaimDetailsAtService_optimised, fact_claim_data, etl_icd_mapping, etl_episode_work, episode_classification, episode_condition_group
   - Related Gold View: vw_HCS_Claims
   - Bronze Tables: Only those used by the 6 SPs (22 tables total)

4. **If user specifies `full` option:**
   - Restore the complete lineage diagram with all 17 Gold Views, 29 Silver Tables, 29 SPs, and 88 Bronze Tables

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
/lineage full                    # Restore complete lineage (all 20 SPs)
```

## HCS Claims Filter Details

When `hcs_claims` option is used, show only these objects:

| SP | Silver Table | Bronze Sources |
|----|--------------|----------------|
| usp_Create_ClaimDetailsAtService_Optimised | ClaimDetailsAtService_optimised | claim_line, cover, cover_product, grouping, membership_group, person, plan_detail, product |
| sp_LoadFactClaimData | fact_claim_data | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, payee |
| usp_Load_ICD_Mapping | etl_icd_mapping | icd_type |
| usp_Load_Episode_Base_Data | etl_episode_work | claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, episode, episode_diagnosis_procedure, medical_item_icd_10am |
| usp_Process_Episode_Classification | episode_classification | icd10_category_map, icd10_d/h/q/r/s/t/z_category_map |
| usp_generate_episode_condition_group | episode_condition_group | (none) |

**Related Gold View:** vw_HCS_Claims (reads ClaimDetailsAtService_optimised, episode_classification, episode_condition_group)

## Output Format

After completing any lineage operation, always display the updated table:

```
## Updated Table Structure

| Table | SP | Bronze Sources |
|-------|-----|----------------|
| AgentAgreementStatus | LoadAgentAgreementStatus | grouping |
| ... | ... | ... |
```
