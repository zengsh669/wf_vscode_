---
name: copilot-kb
description: Build or update a Copilot Agent Knowledge Base MD file for a GOLD.copilot view. Use when the user invokes /copilot-kb, asks to "add a view to the knowledge base", "create a copilot KB", or "document a view for the copilot agent".
argument-hint: "[view_name] — the GOLD.copilot view to document"
allowed-tools: [Read, Write, Edit, Bash, PowerShell]
---

# copilot-kb Skill

Build a structured Markdown knowledge base file for a single `GOLD.copilot` view, following the established architecture. Each view gets its own MD file saved wherever the user specifies (default: `sql_db/`).

Before starting, read the canonical sample for structure and tone reference:
`.claude/skills/copilot-kb/samples/ME_Total_Membership.md`

---

## Architecture Principle

All data exposed to the Copilot Agent must be wrapped as a view within `GOLD.copilot` before being documented. Never point the agent at source tables, `dbo` objects, SILVER, or BRONZE directly.

- One MD file per view
- If views need to JOIN, create a `data_model.md` alongside the view files

---

## Steps

### 1. Identify the view

If the user provided a view name as `$ARGUMENTS`, use that. Otherwise ask:
> "Which `GOLD.copilot` view would you like to document?"

Confirm the full name: `GOLD.copilot.<view_name>`

### 2. Collect column metadata

Ask the user to run this query and share the results:

```sql
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM GOLD.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'copilot'
  AND TABLE_NAME = '<view_name>'
ORDER BY ORDINAL_POSITION;
```

If the user cannot run this, ask them to paste the Object Explorer column list from SSMS.

### 3. Clarify business context

Ask the following questions **one at a time**, waiting for answers before proceeding:

1. **Purpose** — What business question does this view answer? Who are the likely users?
2. **Refresh frequency** — How often is the data updated? Is current-month data available or always lagged?
3. **Granularity** — Run this query and share results. If 0 rows returned, the combination is a unique key:
   ```sql
   SELECT <all_columns_except_measures>, COUNT(*) AS Row_Count
   FROM GOLD.copilot.<view_name>
   GROUP BY <all_columns_except_measures>
   HAVING COUNT(*) > 1
   ORDER BY Row_Count DESC;
   ```
4. **Measure columns** — Which columns are counts/amounts (not dimensions)?
5. **Code columns** — Are any columns codes without a description column (like `H`, `K`, `SA`)? If so, is the lookup available?
6. **Known pitfalls** — Any date format issues, snapshot vs cumulative confusion, or filter conditions users always need?

### 4. Draft the MD file

Create the file at the user's preferred location (default: `sql_db/<view_name>.md`).

Follow the structure and tone of the sample at `.claude/skills/copilot-kb/samples/ME_Total_Membership.md`. Use this template:

```markdown
# View: GOLD.copilot.<view_name>

**Last updated:** <today's date>
**Maintained by:** Shawn Zeng

## Description
<business purpose, who uses it, what question it answers>

## Data Refresh
<frequency, lag explanation, how to get latest month if applicable>

## Granularity
<unique key columns, confirmed by query or noted as unverified>

## Columns

| Column Name | Data Type | Nullable | Description |
|-------------|-----------|----------|-------------|
| ...         | ...       | ...      | ...         |

## Important Notes
- <date format gotchas>
- <snapshot vs cumulative>
- <code columns — return raw, don't interpret>
- <always use TOP unless aggregating>

## Example Queries

### Business user questions
<2-3 natural language questions with SQL>

### Analyst questions
<2-3 more complex questions with SQL>

## Glossary

| Term | Meaning |
|------|---------|
| ...  | ...     |

## Known Limitations
- <what this view cannot answer>
- <related data not available>
```

### 5. Verify SQL examples

Before writing the file, mentally check each example query:
- Column names wrapped in `[square brackets]` if they contain spaces
- Date filtering uses `EOMONTH(DATEADD(MONTH, -1, GETDATE()))` not `EOMONTH(@year, @month-1)`
- `TOP 1000` included on row-level queries
- Full three-part name `GOLD.copilot.<view_name>` used throughout

### 6. Update the main knowledge base index

If a main `copilot_knowledge_base.md` index file exists in the same directory, add the new view to its **Permitted Data Source** table:

```markdown
| GOLD | copilot | <view_name> | <one-line description> |
```

If no index file exists, ask the user whether to create one.

### 7. Confirm completion

Report to the user:
- Path of the new view MD file
- Whether the main index was updated
- Any columns or business rules that could not be confirmed and need follow-up
