---
name: lineage
description: Update the data warehouse lineage diagram (Gold Views, Silver Tables, Silver SPs)
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "[add/remove/update] [object details]"
---

# Data Lineage Management Skill

You are helping manage the data warehouse lineage diagram.

## Key Files

| File | Purpose |
|------|---------|
| `sql_db/DWH_/Database/data_lineage.html` | The lineage visualization (Mermaid.js) |
| `sql_db/DWH_/Database/gold_view.ipynb` | Gold Views definitions |
| `sql_db/DWH_/Database/silver_tbl_sp.ipynb` | Silver Tables & SPs definitions |

## Architecture

```
Gold Views ──reads──> Silver Tables <──loads── Silver SPs <──reads── Bronze Tables
     │                                                              ↑
     └──────────────────── (direct access) ─────────────────────────┘
```

## Current Objects (as of 2026-02-03)

### Gold Views (15)
- Claim_Aggr -> Claim_Fact
- Claim_Val -> Claim_Detail, Product, Hospital_Lookup, Ancillary_Lookup
- ME_Membership_Joins -> Membership_Group_Key, Product
- ME_Membership_Terminations -> Membership_Group_Key, Product, Membership_History, Termination_Code
- ME_Total_Membership -> Membership_Group_Key, Product
- Membership_Budget -> Membership_Budget, Product
- Membership_Movement -> Membership_Group_Key, Product
- Membership_Product_Type -> Membership_Group_Key
- Membership_Reporting -> Membership_Group_Key, Product, Membership_History, Termination_Code
- vw_calculated_deficit_amb_levies_output -> calculated_deficit_amb_levies
- vw_gross_deficit -> abp_details
- vw_HCS_Claims -> ClaimDetailsAtService_optimised, episode_classification, episode_condition_group (+ Bronze tables)
- vw_RebateLineCheck -> (Direct Bronze)
- vw_RebateRegistrations -> (Direct Bronze)
- vw_RebateReminders -> RebateReminders (+ Bronze tables: MemberBranch, MemberCover, MemberRebate, PersonContact, person, person_membership, web_security)

### Silver Tables (22) with corresponding SPs and Bronze Sources
| Table | SP | Bronze Sources |
|-------|-----|----------------|
| abp_details | usp_refresh_abp_details | ClaimDetailGenAndHosp, ClaimDetailsAtService, claim_line, memship, person |
| AgentAgreementStatus | LoadAgentAgreementStatus | grouping |
| Ancillary_Lookup | usp_Load_Ancillary_Lookup | claim_line, cover, cover_product |
| ArrearsReport | Load_ArrearsReportPayroll | MemberAgent, MemberBranch, MemberCover, MemberGroup, billing_group, billing_type, grouping, memship, person, person_membership, security_level, web_security |
| calculated_deficit_amb_levies | usp_load_calculated_deficit_amb_levies | group_key_full_by_branch |
| Claim_Detail | Claim_Detail_Load | claim_generalitem, claim_hospitalitem, claim_line, group_key_full_by_branch, person |
| Claim_Fact | Load_Claim_Fact | claim_generalitem, claim_hospitalitem, claim_line, cover, cover_product, person, product, provider, provider_number |
| ClaimDetailsAtService_optimised | usp_Create_ClaimDetailsAtService_Optimised | claim_line, cover, cover_product, grouping, membership_group, person, plan_detail, product |
| Deceased_Active_Membership | usp_Deceased_Active_Membership | MemberGroup, memship, person, person_membership, security_level |
| episode_classification | usp_Process_Episode_Classification | icd10_category_map, icd10_d_category_map, icd10_h_category_map, icd10_q_category_map, icd10_r_category_map, icd10_s_category_map, icd10_t_category_map, icd10_z_category_map |
| episode_condition_group | usp_generate_episode_condition_group | - |
| etl_episode_work | usp_Load_Episode_Base_Data | ClaimDetailGenAndHosp, claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type, episode, episode_diagnosis_procedure, medical_item_icd_10am |
| etl_icd_mapping | usp_Load_ICD_Mapping | icd_type |
| fact_claim_data | sp_LoadFactClaimData | ClaimDetailGenAndHosp, claim_line |
| Hospital_Lookup | usp_Load_Hospital_Lookup | claim_line, cover, cover_product |
| Membership_Budget | Membership_Budget_Load | Membership_Channel_Budget, Membership_Product_Budget, Membership_Product_Map |
| Membership_Group_Key | Membership_Group_Key_Load | Membership_Channel_Map, Membership_Fund_Map, group_key_full_by_branch |
| Membership_History | Membership_History_Load | - |
| Product | Product_Load | Membership_Product_Map, product |
| provider_claim | usp_Load_provider_claim | billing_agent, payment, person, provider_claim, provider_claim_eclipse, provider_claim_line |
| RebateReminders | Load_RebateReminders | MemberRebate, PersonAddressHomePostal, PersonContact, memship, person, person_membership, web_security |
| Termination_Code | Termination_Code_Load | Membership_Termination_Map, termination_code |

### Bronze Tables (64) by Category

| Category | Tables |
|----------|--------|
| Claim Tables | ClaimDetailGenAndHosp, ClaimDetailsAtService, claim_generalitem, claim_hospitalitem, claim_line, claim_line_status_type |
| Member Tables | MemberAgent, MemberBranch, MemberCover, MemberGroup, MemberRebate, membership_group, memship, person, person_membership |
| Membership Config | Membership_Channel_Budget, Membership_Channel_Map, Membership_Fund_Map, Membership_Product_Budget, Membership_Product_Map, Membership_Termination_Map |
| Person Tables | PersonAddressHomePostal, PersonContact |
| Billing Tables | billing_agent, billing_group, billing_type, payment |
| Cover Tables | cover, cover_product, cover_type, fund_classification, plan_detail, product |
| Episode Tables | episode, episode_diagnosis_procedure, medical_item_icd_10am |
| ICD Mapping | icd10_category_map, icd10_d_category_map, icd10_h_category_map, icd10_q_category_map, icd10_r_category_map, icd10_s_category_map, icd10_t_category_map, icd10_z_category_map, icd_type |
| Rebate Tables | hic_rebate_error, hic_rebate_segment, hic_rebate_segment_error, in_rebate, rebate_reg_errors |
| Provider Tables | provider, provider_claim, provider_claim_eclipse, provider_claim_line, provider_number, provider_type |
| Other Tables | group_key_full_by_branch, grouping, item, item_group, security_level, service_type, termination_code, web_security |

## Task Instructions

When user invokes `/lineage`, follow these steps:

1. **If user wants to add/remove/update objects:**
   - Read the current `data_lineage.html`
   - Modify the Mermaid diagram accordingly
   - Update the statistics numbers
   - Update this SKILL.md file with the new object list

2. **If user wants to regenerate from notebooks:**
   - Extract objects from `gold_view.ipynb` and `silver_tbl_sp.ipynb`
   - Analyze SQL to find dependencies (FROM SILVER.dbo.XXX and FROM BRONZE.dbo.XXX)
   - Regenerate the complete lineage HTML

3. **IMPORTANT: Always show updated table at the end of conversation:**
   - After any lineage operation (add/remove/update/regenerate), display the updated "Silver Tables with SPs and Bronze Sources" table in the chat
   - This helps user verify the changes immediately

4. **HTML Structure Reference:**
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
/lineage update - Gold View "Claim_Val" now also reads "NewTable"
/lineage regenerate from notebooks
```

## Output Format

After completing any lineage operation, always display the updated table:

```
## Updated Table Structure

| Table | SP | Bronze Sources |
|-------|-----|----------------|
| abp_details | usp_refresh_abp_details | ClaimDetailGenAndHosp, ClaimDetailsAtService, ... |
| ... | ... | ... |
```
