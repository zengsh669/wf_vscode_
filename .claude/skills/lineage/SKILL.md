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
Gold Views ──reads──> Silver Tables <──loads── Silver SPs
```

## Current Objects (as of 2026-01-28)

### Gold Views (7)
- Claim_Aggr -> Claim_Fact
- Claim_Val -> Claim_Detail, Product, Hospital_Lookup, Ancillary_Lookup
- vw_calculated_deficit_amb_levies_output -> calculated_deficit_amb_levies
- vw_gross_deficit -> abp_details
- vw_RebateReminders -> RebateReminders
- vw_RebateLineCheck -> (Direct Bronze)
- vw_RebateRegistrations -> (Direct Bronze)

### Silver Tables (20) with corresponding SPs
| Table | SP |
|-------|-----|
| abp_details | usp_refresh_abp_details |
| AgentAgreementStatus | LoadAgentAgreementStatus |
| Ancillary_Lookup | usp_Load_Ancillary_Lookup |
| ArrearsReport | Load_ArrearsReportPayroll |
| calculated_deficit_amb_levies | usp_load_calculated_deficit_amb_levies |
| Claim_Detail | Claim_Detail_Load |
| Claim_Fact | Load_Claim_Fact |
| episode_classification | usp_Process_Episode_Classification |
| episode_condition_group | usp_generate_episode_condition_group |
| etl_episode_work | usp_Load_Episode_Base_Data |
| etl_icd_mapping | usp_Load_ICD_Mapping |
| fact_claim_data | sp_LoadFactClaimData |
| Hospital_Lookup | usp_Load_Hospital_Lookup |
| Membership_Budget | Membership_Budget_Load |
| Membership_Group_Key | Membership_Group_Key_Load |
| Membership_History | Membership_History_Load |
| Product | Product_Load |
| provider_claim | usp_Load_provider_claim |
| RebateReminders | Load_RebateReminders |
| Termination_Code | Termination_Code_Load |

## Task Instructions

When user invokes `/lineage`, follow these steps:

1. **If user wants to add/remove/update objects:**
   - Read the current `data_lineage.html`
   - Modify the Mermaid diagram accordingly
   - Update the statistics numbers
   - Update this SKILL.md file with the new object list

2. **If user wants to regenerate from notebooks:**
   - Extract objects from `gold_view.ipynb` and `silver_tbl_sp.ipynb`
   - Analyze SQL to find dependencies (FROM SILVER.dbo.XXX)
   - Regenerate the complete lineage HTML

3. **HTML Structure Reference:**
   ```
   G# = Gold View node
   S# = Silver Table node
   SP# = Stored Procedure node

   G# --> S#      (solid = View reads Table)
   S# -.-> SP#    (dashed = SP loads Table)

   Colors:
   - Gold: #ffd700
   - Silver: #c0c0c0
   - SP: #4ecdc4
   - Direct Bronze View: #ffa500
   ```

## Example Usage

```
/lineage add Silver table "NewTable" with SP "Load_NewTable"
/lineage remove Silver table "OldTable"
/lineage update - Gold View "Claim_Val" now also reads "NewTable"
/lineage regenerate from notebooks
```
