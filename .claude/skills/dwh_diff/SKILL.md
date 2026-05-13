---
name: dwh_diff
description: Compare DWH notebook versions between the last two git commits — reports added, removed, and modified Gold Views / Silver Tables / Silver SPs with clean SQL line diffs
argument-hint: "[optional: HEAD~N to compare a specific earlier commit]"
---

# DWH Diff Skill

**语言要求（强制）：与用户的所有沟通必须使用简体中文。禁止使用韩文、日文或其他语言。**

Compare `gold_view.ipynb` and `silver_tbl_sp.ipynb` between the two most recent git commits and produce a structured change report.

## Target Files

| File | Contains |
|------|----------|
| `sql_db/DWH_/Database/gold_view.ipynb` | All GOLD views |
| `sql_db/DWH_/Database/silver_tbl_sp.ipynb` | All SILVER tables + stored procedures |

## Steps

### 1. Resolve commits to compare

Default: compare `HEAD~1` (previous commit) vs `HEAD` (current commit).

If the user passes an argument like `HEAD~3`, use that as the old commit instead.

Get commit metadata for the report header:
```
git log --pretty=format:"%H %ad %s" --date=short -5
```

### 2. Extract notebook content for both commits

For each of the two files, extract the raw JSON from both commits:
```
git show <old_commit>:sql_db/DWH_/Database/gold_view.ipynb
git show <new_commit>:sql_db/DWH_/Database/gold_view.ipynb
```

Use PowerShell to parse the JSON (files have UTF-8 BOM — use `-Encoding UTF8` and `ConvertFrom-Json`).

### 3. Parse objects from notebook cells

Notebook structure: markdown cells act as section headers (object name), followed by one or more code cells containing the SQL DDL.

Parse rule:
- A **markdown cell** whose source matches `# [dbo].[...]` starts a new object block
- All **code cells** immediately following belong to that object
- Concatenate all code cell sources to form the full SQL for that object

Extract the object name from the markdown header (strip `# ` prefix and trim whitespace).

Classify each object by its SQL content:
- Contains `CREATE VIEW` → **GOLD View**
- Contains `CREATE TABLE` → **SILVER Table**
- Contains `CREATE PROCEDURE` or `CREATE PROC` → **SILVER Stored Procedure**

Build two dictionaries (old version, new version):
```
{ object_name: { type: "view"|"table"|"sp", sql: "..." } }
```

### 4. Diff the object sets

Compare old vs new dictionaries:

- **Added**: key exists in new, not in old
- **Removed**: key exists in old, not in new
- **Modified**: key exists in both, but SQL content differs (after stripping leading/trailing whitespace from each line)

### 5. For modified objects — compute line-level SQL diff

For each modified object:
1. Split old SQL and new SQL into lines
2. Produce a unified diff (removed lines prefixed `-`, added lines prefixed `+`)
3. Show only changed lines plus 2 lines of context above/below each change
4. Skip lines that only differ in whitespace at line start/end (cosmetic indentation changes)

Use PowerShell to compute the diff — compare-object or manual line comparison.

### 6. Output the report

Output in the following format (in 简体中文 labels):

```
========================================
DWH 变更报告
对比: <old_commit_short> (<old_date> "<old_message>")
  →  <new_commit_short> (<new_date> "<new_message>")
========================================

── 新增 ────────────────────────────────

GOLD Views (N):
  + [dbo].[vw_NewView]

SILVER Tables (N):
  (无)

SILVER Stored Procedures (N):
  + [dbo].[usp_Load_NewTable]

── 删除 ────────────────────────────────

GOLD Views (N):
  - [dbo].[OldView]

SILVER Tables (N):
  (无)

SILVER Stored Procedures (N):
  (无)

── 修改 ────────────────────────────────

GOLD Views (N):

  ~ [dbo].[Claim_Aggr]
    ...
      JOIN Silver.dbo.Claim_Fact cf ON ...
    - WHERE cf.ClaimDate >= '2024-01-01'
    + WHERE cf.ClaimDate >= '2025-01-01'
    ...

SILVER Tables (N):
  (无)

SILVER Stored Procedures (N):

  ~ [dbo].[usp_Load_Membership]
    ...
    - INSERT INTO Membership_History
    + INSERT INTO Membership_History WITH (TABLOCK)
    ...

========================================
总计: +N 新增  -N 删除  ~N 修改
========================================
```

## Notes

- If either file has no changes between commits, skip it silently (don't report "no changes" for that file separately — the section "(无)" entries are sufficient).
- If both files are identical between commits, output: `两个版本之间没有检测到任何变更。`
- Ignore changes to notebook metadata (kernel info, cell execution counts, outputs) — only compare cell `source` content.
- Object names are case-sensitive — treat `[dbo].[Claim_Aggr]` and `[dbo].[claim_aggr]` as different objects.
