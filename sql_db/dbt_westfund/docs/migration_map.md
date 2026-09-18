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

Naming settled on `stg_<bronze_table>` (no `bronze__` infix — staging is
already understood to map 1:1 to Bronze).

| Bronze table | dbt model | Status | Used by lines |
|---|---|---|---|
| claim_generalitem | stg_claim_generalitem | Verified in Sandbox | Line 1 |
| claim_hospitalitem | stg_claim_hospitalitem | Verified in Sandbox | Line 1 |
| claim_line | stg_claim_line | Verified in Sandbox | Line 1 |
| cover | stg_cover | Verified in Sandbox | Line 1 |
| cover_product | stg_cover_product | Verified in Sandbox | Line 1 |
| person | stg_person | Verified in Sandbox | Line 1 |
| product | stg_product | Verified in Sandbox | Line 1 |
| provider | stg_provider | Verified in Sandbox | Line 1 |
| provider_number | stg_provider_number | Verified in Sandbox | Line 1 |

"Verified in Sandbox" here means: builds cleanly via `dbt build`, and
`stg_claim_line` has data-quality tests attached (`claim_type`
accepted_values, `claim_id` not_null, `claim_line_id` unique — all
`severity: warn`, see notes below). The other 8 staging models have
description/tests placeholders only. Row-by-row content comparison against
Bronze (via `sql_db/dbt_westfund/tests/compare_sandbox_vs_prod.ipynb`) is
in progress, not yet complete for all 9.

## Shared intermediate (Silver) models (source of truth for intermediate status)

| Silver table | dbt model | Status | Used by lines / downstream models |
|---|---|---|---|
| Claim_Fact | itm_claim_fact | Verified in Sandbox | Line 1 |

## Line 1: Claim_Fact → Claim_Aggr

Source: `sql_db/DWH_/Database/data_lineage_table.html` ("Claims & Lookups"
section). Clean 3-layer chain — Gold reads only Silver here, no direct
Bronze dependency.

| Original SP/View | Source DB.Schema.Object | dbt model | Layer | Status |
|---|---|---|---|---|
| (n/a — source table) | BRONZE.dbo.claim_generalitem | stg_claim_generalitem | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.claim_hospitalitem | stg_claim_hospitalitem | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.claim_line | stg_claim_line | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.cover | stg_cover | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.cover_product | stg_cover_product | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.person | stg_person | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.product | stg_product | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.provider | stg_provider | staging | Verified in Sandbox |
| (n/a — source table) | BRONZE.dbo.provider_number | stg_provider_number | staging | Verified in Sandbox |
| Load_Claim_Fact | SILVER.dbo.Claim_Fact | itm_claim_fact (alias: `Claim_Fact`) | intermediate | Verified in Sandbox |
| (view) Claim_Aggr | GOLD.dbo.Claim_Aggr | mart_claim_aggr (alias: `Claim_Aggr`) | marts | Verified in Sandbox |

**11 models total** (9 staging, 1 intermediate, 1 marts) for this line —
all 11 build successfully end-to-end via `dbt build --select staging+`.

### Notes for this line
- Silver (`Claim_Fact`) only reads from the 9 Bronze staging models above —
  no dependency on any other Silver table.
- Gold (`Claim_Aggr`) only reads from `Claim_Fact` — no direct Bronze
  dependency, so this is a clean textbook 3-layer chain (unlike the
  ClaimDetailsAtService_optimised → vw_Calculated_Deficit line considered
  earlier, where Gold reads Bronze directly).
- Model aliases (`config.alias`) are set to match production object casing
  (`Claim_Fact`, `Claim_Aggr`) — the dbt model/file names stay lowercase
  per dbt convention, but the physical SQL Server objects match Silver/Gold
  exactly. This was fixed after an initial mismatch was found by comparing
  Sandbox vs. production object names directly (Sandbox originally had
  lowercase `claim_fact` / `claim_aggr`).
- `itm_claim_fact` takes ~8-9 minutes to build (510s in the most recent
  run). Root cause: three repeated correlated subqueries against the
  `member_details` CTE (translated faithfully from the original SP, not
  yet optimised — see `poc_progress.md` for the performance investigation).
  Staging materialization (view vs. table) was tested as a secondary
  factor and is not the main driver.
- `stg_claim_line.claim_line_id` unique test fails with 411 duplicates
  (severity: warn, not error) — expected, since `claim_line` is a
  line-level detail table; a true unique key would need to be a composite
  of `claim_id` + `claim_line_id`. Kept as a warn-level test intentionally,
  as a live demo of dbt's automated data-quality testing.
- Row-by-row validation against production (`itm.Claim_Fact` vs.
  `SILVER.dbo.Claim_Fact`, `mart.Claim_Aggr` vs. `GOLD.dbo.Claim_Aggr`) is
  in progress via `sql_db/dbt_westfund/tests/compare_sandbox_vs_prod.ipynb`
  — no primary key is defined on either object, so the comparison covers
  column names, row counts, dtypes, null rates, numeric column sums, and
  categorical value sets (not full row-level equality).
