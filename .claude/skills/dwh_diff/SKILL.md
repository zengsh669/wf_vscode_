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

## Environment Notes (confirmed from testing)

- **Python is not available** — use PowerShell for all parsing and diff logic
- **Files have UTF-8 BOM** — always read with `-Encoding UTF8` then `ConvertFrom-Json`; do NOT use `Get-Content | ConvertFrom-Json` directly on the raw path without encoding
- **Temp files** go to `$env:TEMP`; they are overwritten on each run and auto-cleaned by Windows — no manual cleanup needed
- **VS Code diff**: `code --diff` does not work in this environment; use the full path `& "C:\Users\zengsh\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd" --diff <old> <new>`
- **Output size**: PowerShell output beyond ~30KB is truncated by the harness. Never dump all diffs in one call — output the summary report first, then handle VS Code diff per object separately

## Steps

### 1. Resolve commits to compare

Default: compare `HEAD~1` (previous commit) vs `HEAD` (current commit).

If the user passes an argument like `HEAD~3`, use that as the old commit instead.

Get commit metadata for the report header:
```
git log --pretty=format:"%H %ad %s" --date=short -5
```

### 2. Extract notebook content for both commits

Extract raw JSON from both commits into temp files using PowerShell:
```powershell
git show HEAD~1:sql_db/DWH_/Database/silver_tbl_sp.ipynb | Out-File "$env:TEMP\silver_old.json" -Encoding UTF8
git show HEAD:sql_db/DWH_/Database/silver_tbl_sp.ipynb   | Out-File "$env:TEMP\silver_new.json" -Encoding UTF8
git show HEAD~1:sql_db/DWH_/Database/gold_view.ipynb     | Out-File "$env:TEMP\gold_old.json" -Encoding UTF8
git show HEAD:sql_db/DWH_/Database/gold_view.ipynb       | Out-File "$env:TEMP\gold_new.json" -Encoding UTF8
```

Then parse with `Get-Content <path> -Raw -Encoding UTF8 | ConvertFrom-Json`.

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

Before comparing, **normalize** each object's SQL:
- Filter out lines matching `Script Date:` — SQL Server export stamps a timestamp on every object; this is not a real change and will cause every object to appear modified if not removed
- Trim each line (leading/trailing whitespace)
- Remove blank lines
- Strip `\r` (CRLF → LF)

Then compare old vs new normalized SQL:

- **Added**: key exists in new, not in old
- **Removed**: key exists in old, not in new
- **Modified**: key exists in both, but normalized SQL differs

**Use set-based comparison (not sequential line diff) to detect modifications** — a sequential diff algorithm will produce false positives when line order is preserved but content is identical. Compare the normalized line sets: lines only in old = removed, lines only in new = added.

### 5. Output the summary report

Output the full structured report first (新增 / 删除 / 修改 counts and names). Do NOT include line-level diffs in this report — output size will exceed the harness limit.

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
  (无)

SILVER Tables (N):
  (无)

SILVER Stored Procedures (N):
  ~ [dbo].[usp_Load_Earned_Contributions]
  ~ [dbo].[Load_Claim_Fact]

========================================
总计: +N 新增  -N 删除  ~N 修改
========================================
```

### 6. Offer VS Code diff for modified objects

After the summary report, if there are any modified objects, ask the user which one(s) they want to inspect in VS Code diff view.

List the modified objects with numbers, e.g.:
```
如需在 VS Code 中查看具体修改，请选择：
1. [dbo].[usp_Load_Earned_Contributions]
2. [dbo].[Load_Claim_Fact]
```

When the user picks a number:
1. Write the old SQL to `$env:TEMP\old_<ObjectName>.sql`
2. Write the new SQL to `$env:TEMP\new_<ObjectName>.sql`
3. Open VS Code diff:
```powershell
& "C:\Users\zengsh\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd" --diff "$env:TEMP\old_<ObjectName>.sql" "$env:TEMP\new_<ObjectName>.sql"
```

The temp files are overwritten on each run and auto-cleaned by Windows.

## Notes

- If either file has no changes between commits, skip it silently (don't report "no changes" for that file separately — the section "(无)" entries are sufficient).
- If both files are identical between commits, output: `两个版本之间没有检测到任何变更。`
- Ignore changes to notebook metadata (kernel info, cell execution counts, outputs) — only compare cell `source` content.
- Object names are case-sensitive — treat `[dbo].[Claim_Aggr]` and `[dbo].[claim_aggr]` as different objects.
- The `gold_view.ipynb` file may not have changed between commits — check with `git diff --name-only HEAD~1 HEAD` first and skip parsing it if unchanged.
