# Copilot Agent Knowledge Base
# Westfund Membership Data

**Last updated:** 2026-05-27  
**Maintained by:** Shawn Zeng

---

## Purpose

This document defines the data available to this Copilot Agent and the rules for querying it. The agent must only query the views listed in this document. No other tables, views, or schemas are permitted.

---

## Permitted Data Source

The agent may **only** query views in the `GOLD.copilot` schema.

| Database | Schema | View Name | Description |
|----------|--------|-----------|-------------|
| GOLD | copilot | ME_Total_Membership | Monthly membership policy counts by product |

**Connection:** SQL Server `prdsql05.westfund.com.au`, Database `GOLD`

---

## View: `GOLD.copilot.ME_Total_Membership`

### Description

Monthly snapshot of Westfund membership policy counts, broken down by product type, product cover, product code, and product group. Each row represents a unique combination of these dimensions for a given month.

### Columns

| Column Name | Data Type | Nullable | Description |
|-------------|-----------|----------|-------------|
| Run Month | date | Yes | The month of the snapshot, stored as the last day of the month (e.g., `2024-05-31` = May 2024) |
| Product Type | varchar(1) | No | Single-character code identifying the product type category |
| Product Cover | varchar(2) | Yes | Two-character code identifying the cover type within a product type |
| Product | decimal(9,0) | Yes | Numeric product code |
| Product Group | varchar(60) | Yes | Full descriptive name of the product group (e.g., `Silver Plus Assure`, `Bronze Hospital`) |
| Policies | int | Yes | Number of active policies for this combination in the given month |

### Data Refresh

This view is refreshed **once per month, at month-end**. The most recent available data is always the previous completed month — for example, if today is 27 May 2026, the latest `Run Month` will be `2026-04-30`. Current-month data is not available until the month closes.

To get the latest available month, always use:
```sql
SELECT MAX([Run Month]) FROM GOLD.copilot.ME_Total_Membership;
```

### Granularity

Each row is uniquely identified by the combination of `[Run Month]`, `[Product Type]`, `[Product Cover]`, and `[Product]`. There are no duplicate rows. `COUNT(*)` and `SUM([Policies])` will give correct results without needing `DISTINCT`.

### Important Notes

- **`Run Month` is always the last day of the month** — to filter by month, use `EOMONTH()` or match on the last day (e.g., `'2024-05-31'`).
- **`Policies` is a snapshot count**, not a cumulative total — summing across months will overcount.
- **`Product Type` and `Product Cover` are codes**, not descriptions — the agent should return the raw values and let the user interpret them, or filter only when the user specifies the exact code.
- **Always include a `TOP` clause** unless the user explicitly asks for all rows, to avoid returning large result sets.

---

## Query Rules

The agent must follow these rules when generating SQL:

1. Only query `GOLD.copilot.ME_Total_Membership` — no other tables or views.
2. Always use `TOP 1000` by default unless the user asks for all data or an aggregation.
3. Wrap column names in square brackets (e.g., `[Run Month]`, `[Product Group]`) because they contain spaces.
4. Use `EOMONTH(DATEADD(MONTH, -1, GETDATE()))` or explicit date literals like `'2024-05-31'` when filtering by month.
5. Do not return raw PII — this view contains no personal member data, but avoid row-level dumps when a summary suffices.
6. If the user's question is ambiguous, return a grouped/aggregated result rather than row-level detail.

---

## Example Queries

### Business user questions

**"How many policies did Westfund have last month?"**
```sql
SELECT SUM([Policies]) AS Total_Policies
FROM GOLD.copilot.ME_Total_Membership
WHERE [Run Month] = EOMONTH(DATEADD(MONTH, -1, GETDATE()));
```

**"What are the current product groups?"**
```sql
SELECT DISTINCT [Product Group]
FROM GOLD.copilot.ME_Total_Membership
WHERE [Run Month] = (SELECT MAX([Run Month]) FROM GOLD.copilot.ME_Total_Membership)
ORDER BY [Product Group];
```

**"How many policies does Silver Plus Assure have this month?"**
```sql
SELECT SUM([Policies]) AS Total_Policies
FROM GOLD.copilot.ME_Total_Membership
WHERE [Product Group] = 'Silver Plus Assure'
  AND [Run Month] = (SELECT MAX([Run Month]) FROM GOLD.copilot.ME_Total_Membership);
```

---

### Analyst questions

**"Show me monthly policy trends for the last 12 months, by product group."**
```sql
SELECT
    [Run Month],
    [Product Group],
    SUM([Policies]) AS Total_Policies
FROM GOLD.copilot.ME_Total_Membership
WHERE [Run Month] >= DATEADD(MONTH, -12, EOMONTH(GETDATE()))
GROUP BY [Run Month], [Product Group]
ORDER BY [Run Month] DESC, Total_Policies DESC;
```

**"Which product groups have grown the most over the past 6 months?"**
```sql
WITH Latest AS (
    SELECT [Product Group], SUM([Policies]) AS Current_Policies
    FROM GOLD.copilot.ME_Total_Membership
    WHERE [Run Month] = (SELECT MAX([Run Month]) FROM GOLD.copilot.ME_Total_Membership)
    GROUP BY [Product Group]
),
SixMonthsAgo AS (
    SELECT [Product Group], SUM([Policies]) AS Prior_Policies
    FROM GOLD.copilot.ME_Total_Membership
    WHERE [Run Month] = EOMONTH(DATEADD(MONTH, -6, GETDATE()))
    GROUP BY [Product Group]
)
SELECT
    l.[Product Group],
    s.Prior_Policies,
    l.Current_Policies,
    l.Current_Policies - s.Prior_Policies AS Growth
FROM Latest l
LEFT JOIN SixMonthsAgo s ON l.[Product Group] = s.[Product Group]
ORDER BY Growth DESC;
```

**"Break down policies by Product Type for the latest month."**
```sql
SELECT
    [Product Type],
    SUM([Policies]) AS Total_Policies
FROM GOLD.copilot.ME_Total_Membership
WHERE [Run Month] = (SELECT MAX([Run Month]) FROM GOLD.copilot.ME_Total_Membership)
GROUP BY [Product Type]
ORDER BY Total_Policies DESC;
```

---

## Glossary

| Term | Meaning |
|------|---------|
| Run Month | The reporting month, stored as the last calendar day of that month |
| Policies | Count of active membership policies — not members or persons. A single policy may cover multiple people (e.g., a family policy). Do not interpret `Policies` as a headcount. |
| Product Group | The full product name as marketed (e.g., `Bronze Hospital`, `Silver Plus Assure`) |
| Product | Internal numeric product code — use `Product Group` for readable output |
| Snapshot | This data is point-in-time per month; do not sum `Policies` across months |

---

## Known Limitations

- **No member demographics** — this view has no age, gender, location, or member-level data.
- **No claims data** — policy counts only; claims are in separate views not currently available to this agent.
- **Code values unexplained** — `Product Type` (e.g., `H`) and `Product Cover` (e.g., `K`, `SA`) are internal codes whose full lookup table is not available in this knowledge base. Return the raw code to the user.
- **Historical data** — the earliest available `Run Month` should be confirmed by running `SELECT MIN([Run Month]) FROM GOLD.copilot.ME_Total_Membership`.

---

## Fallback Response

If the user's question cannot be answered using the available view, the agent must respond with:

> *"This information is not available in the current dataset. Please raise a request with IT for further assistance."*

Do not attempt to query outside the permitted schema or infer data that is not present.

---

## Out of Scope

The agent must **not**:
- Query any table or view outside `GOLD.copilot` schema
- Attempt to JOIN to SILVER, BRONZE, or `dbo` objects
- Infer data that is not in this view
- Return more than 10,000 rows in a single response

## Architecture Principle

All data exposed to this agent — regardless of its origin (other databases, raw tables, external sources) — must be wrapped as a view within `GOLD.copilot` before being made available. The agent will never be pointed directly at source tables or other databases. This keeps the permission boundary, query rules, and knowledge base structure stable as the dataset grows.
