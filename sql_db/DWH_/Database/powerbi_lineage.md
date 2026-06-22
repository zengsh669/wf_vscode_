# Power BI Report → SQL Server Lineage

---

## Montly Membership Report

**Workspace:** All Staff  
**Size Bucket(MB):** 150  
**Scheduled Refresh:** At 9:05 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *dim_yr table to 2027*
- *Homepage/Equation design*
- *Movement page Logic*

**Tables / Views:**
- GOLD · `TBD`
- SILVER · `TBD`

---

## Gross Margin Report

**Workspace:** Cross-Functional  
**Size Bucket(MB):** 50  
**Scheduled Refresh:** At 9:30 AM on day(s) 13 of every month  
***Notes:***
- *DimDate till 30/06/2027*
- *Access control check*
- *Hompage design*
- *Dynamic format*
- *Data label/Time intelligent measures*
- *Bookmarks*

**Tables / Views:**
- GOLD · `dbo.vw_calculated_deficit_amb_levies_output`; `dbo.Claim_Aggr`; `GOV.vw_glossary_hierarchy`
- SILVER · `dbo.Product`; `dbo.Earned_Contributions`

---

## Telephone System Dashboard

**Workspace:** --  
**Size Bucket(MB):** 50  
**Scheduled Refresh:** At 9:40 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *References from QMS template "https://ei-mysupport-kb.smartsupportapp.com/articles/962-Install%2FUpdate-Power-BI-template?view_portal_id=1592"*
- *Dynamic format*
- *Access control check*
- *Clustered bar logic*

**Tables / Views:**
- GOLD · `--`
- SILVER · `dbo.QMS_Recording_Detail` 

---

## Portfolio Dashboard

**Workspace:** Project Management Office  
**Size Bucket(MB):** 1  
**Scheduled Refresh:** Manual upon request  
***Notes:***
- *DimDate till 30/06/2027*
- *CLustered bar rounded end*； Gantt custom visual； Drill-through feature； Rownumber calculated field

**Tables / Views:**
- GOLD · `--`
- SILVER · `--` 

---

## Claims Dashboard - HCS

**Workspace:** Health Care Services  
**Size Bucket(MB):** 300  
**Scheduled Refresh:** At 8:15 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *Dynamic measure*
- *General design*
- *Measure folders management*

**Tables / Views:**
- GOLD · `dbo.vw_HCS_Claims`
- SILVER · `--` 

---

## Digital and Core - Monthly Recap

**Workspace:** All Staff  
**Size Bucket(MB):** 1  
**Scheduled Refresh:** At 9:05 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*  
- *Waterfall logic*
- *Power query UDF for data cleansing*
- *Measure folders management*

**Tables / Views:**
- GOLD · `--`
- SILVER · `--` 

---

## Declined HICAPS report

**Workspace:** All Staff  
**Size Bucket(MB):** 10  
**Scheduled Refresh:** At 9:30 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *Dynamic date filter*
- *Table filters*
- *Cross-fact tables filtering logic*
- *receipted_msg_col*

**Tables / Views:**
- GOLD · `--`
- SILVER · `dbo.Declined_Hicaps_Claim` 
- BRONZE · `dbo.hicaps_assessing_code` 

---

## Compensation Claims Paginated Report

**Workspace:** Operations  
**Size Bucket(MB):** 1  
**Scheduled Refresh:** Live with SQL server  
***Notes:***
- *Built with Microsoft Report Buider*

**Tables / Views:**
- GOLD · `--`
- SILVER · `dbo.Claim_Line_Detail`

---

## Retained Members

**Workspace:** Operations  
**Size Bucket(MB):** 5  
**Scheduled Refresh:** At 9:20 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *Simple but comfortable design*

**Tables / Views:**
- GOLD · `--`
- SILVER · `dbo.Retention_Tasklist`; `dbo.Retained_Member`

---

## Rebates

**Workspace:** Operations  
**Size Bucket(MB):** 20  
**Scheduled Refresh:** At 9:00 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*

**Tables / Views:**
- GOLD · `dbo.vw_RebateLineCheck`; `dbo.vw_RebateRegistrations`
- SILVER · `dbo.RebateReminders`

---

## Risk Equalisation Estimation

**Workspace:** Finance  
**Size Bucket(MB):** 1  
**Scheduled Refresh:** At 9:30 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *Calculated deficit measure; SAD_Qtr measure*

**Tables / Views:**
- GOLD · `dbo.vw_Calculated_Deficit`
- SILVER · `--`

---

## Deceased Members on Active Memberships

**Workspace:** Operations  
**Size Bucket(MB):** 50  
**Scheduled Refresh:** At 8:30 AM every Mon, Tue, Wed, Thu, Fri of every week  
***Notes:***
- *DimDate till 30/06/2027*
- *Measure switch logic*
- *Typical star schema*

**Tables / Views:**
- GOLD · `dbo.Claim_Val`
- SILVER · `dbo.Product`; `dbo.Deceased_Active_Membership`

---