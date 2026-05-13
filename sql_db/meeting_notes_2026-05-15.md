# Meeting Notes – 2026-05-13

## Action Items / Follow-ups

- **HCS Dashboard Demo** – Archive Qlik on June 19 *(relevant QVDs?)*
- **Compensation Claims** – Paginated report
- **Declined HICAPS Report**
- **Trev Update** (next week) – WestfundRPA (BOT dashboard); next HCS on PBI?

---

## Dimension Table Proposal

### 1. Define Ownership

We've touched on dim tables in previous catchups but haven't made progress. Clarify the split first:

- **Gus's side (requirements)** — which dim tables we need, which columns, naming conventions, and data types
- **Shawn's side (implementation)** — technical build and deployment

### 2. Two Categories of Tables

**Category A — Already exist in Bronze**
Raw tables that naturally fit dim table characteristics and just need to be cleaned up and promoted to Silver:

| Table |
|-------|
| product |
| sales_channel |
| hicaps_assessing_code |
| cover_type |
| billing_type |
| item_group |

**Category B — Don't exist in Bronze yet**
Need to be created from scratch; source and logic must be defined in requirements doc first:

| Table |
|-------|
| DimDate |
| DimState |

### 3. Proposal

Gus to put together a requirements doc covering:
- What tables we need
- Columns, naming conventions, data types

Once requirements are in place, pick one to pilot the process.
**Suggested pilot: `sales_channel`** — simple, low dependency.
