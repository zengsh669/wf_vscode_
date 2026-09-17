# Migration Map — SP/View → dbt model

Tracks which existing SPs/Views have been translated into dbt models, and
where each stands. Update this after finishing (or starting) each migration
line. For overall POC status/environment setup, see `poc_progress.md`
instead — this file is just the object-by-object mapping.

Status values: `Not started` / `In progress` / `Verified in Sandbox` /
`Deployed to Silver` (future, once CI/CD → Silver is approved)

**A staging or intermediate model can be shared across multiple lines**
(e.g. `person` might feed several Silver tables; `Episode_Detail` feeds
`Episode_Classification`, which itself feeds `vw_HCS_Claims` alongside a
completely separate chain — see `data_lineage_table.html`'s "Silver
Inputs" column for real examples of Silver-to-Silver dependency). A shared
model only gets built once as a file — don't recreate it if a later line
needs it, just `ref()` the existing one. The per-line tables below will
list a shared model more than once for readability, but status should
always match the two "Shared models" tables below, which are the single
source of truth for whether a model actually exists yet. Update both when
a shared model's status changes.

## Shared staging models (source of truth for staging status)

| Bronze table | dbt model | Status | Used by lines |
|---|---|---|---|
| claim_generalitem | stg_bronze__claim_generalitem | Not started | Line 1 |
| claim_hospitalitem | stg_bronze__claim_hospitalitem | Not started | Line 1 |
| claim_line | stg_bronze__claim_line | Not started | Line 1 |
| cover | stg_bronze__cover | Not started | Line 1 |
| cover_product | stg_bronze__cover_product | Not started | Line 1 |
| person | stg_bronze__person | Not started | Line 1 |
| product | stg_bronze__product | Not started | Line 1 |
| provider | stg_bronze__provider | Not started | Line 1 |
| provider_number | stg_bronze__provider_number | Not started | Line 1 |

## Shared intermediate (Silver) models (source of truth for intermediate status)

None built yet — empty until a line's Silver table also feeds another
Silver table (Silver-to-Silver dependency), or the same intermediate model
gets reused by more than one downstream Gold model.

| Silver table | dbt model | Status | Used by lines / downstream models |
|---|---|---|---|
| *(none yet)* | | | |

## Line 1: Claim_Fact → Claim_Aggr

Source: `sql_db/DWH_/Database/data_lineage_table.html` ("Claims & Lookups"
section). Clean 3-layer chain — Gold reads only Silver here, no direct
Bronze dependency.

| Original SP/View | Source DB.Schema.Object | dbt model | Layer | Status |
|---|---|---|---|---|
| (n/a — source table) | BRONZE.dbo.claim_generalitem | stg_bronze__claim_generalitem | staging | Not started |
| (n/a — source table) | BRONZE.dbo.claim_hospitalitem | stg_bronze__claim_hospitalitem | staging | Not started |
| (n/a — source table) | BRONZE.dbo.claim_line | stg_bronze__claim_line | staging | Not started |
| (n/a — source table) | BRONZE.dbo.cover | stg_bronze__cover | staging | Not started |
| (n/a — source table) | BRONZE.dbo.cover_product | stg_bronze__cover_product | staging | Not started |
| (n/a — source table) | BRONZE.dbo.person | stg_bronze__person | staging | Not started |
| (n/a — source table) | BRONZE.dbo.product | stg_bronze__product | staging | Not started |
| (n/a — source table) | BRONZE.dbo.provider | stg_bronze__provider | staging | Not started |
| (n/a — source table) | BRONZE.dbo.provider_number | stg_bronze__provider_number | staging | Not started |
| Load_Claim_Fact | SILVER.dbo.Claim_Fact | claim_fact | intermediate | Not started |
| (view) Claim_Aggr | GOLD.dbo.Claim_Aggr | claim_aggr | marts | Not started |

**11 models total** (9 staging, 1 intermediate, 1 marts) for this line.

### Notes for this line
- Silver (`Claim_Fact`) only reads from the 9 Bronze staging models above —
  no dependency on any other Silver table.
- Gold (`Claim_Aggr`) only reads from `Claim_Fact` — no direct Bronze
  dependency, so this is a clean textbook 3-layer chain (unlike the
  ClaimDetailsAtService_optimised → vw_Calculated_Deficit line considered
  earlier, where Gold reads Bronze directly).
