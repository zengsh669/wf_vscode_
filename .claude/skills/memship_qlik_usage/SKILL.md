---
name: qlik-usage-chart
description: Generate an interactive HTML user session report with per-row sparkline charts from QlikSense session log data (Excel/CSV). Supports breakdown by month, week, or day. Use when the user uploads a QlikSense session log and wants to visualise user activity trends.
---

# QlikSense Usage Chart Skill

Generates a polished, self-contained HTML report from a QlikSense session log file. The report shows a table of users with their session counts broken down by a chosen time period (month / week / day), and a sparkline line chart on each row so trends are immediately visible.

---

## Input

The user provides:
1. **A session log file** — Excel (.xlsx) or CSV with at least these columns:
   - `Session Start` — datetime string, e.g. `2026-02-18 15:49:29`
   - `User ID` — e.g. `WESTFUND\fortunatom`
   - Optionally: `Session Finish`, `Duration`, `Selections`, `CPU Spent (ms)`, `KB Transferred`
2. **A date range** — e.g. "December 2025 to February 2026", "February 2026 only"
3. **A breakdown granularity** — one of:
   - `month` — one column per calendar month
   - `week` — user-defined week ranges, e.g. "02/02–08/02 = W1, 09/02–15/02 = W2"
   - `day` — one column per calendar day within the range
4. *(Optional)* **Filter** — e.g. "only users who appear in all 3 months", "all users"

---

## Steps

### 1. Parse the file

Use Python with `openpyxl` (for .xlsx) or `csv` (for .csv) to read the file from `/mnt/user-data/uploads/`.

Strip the domain prefix from User ID (e.g. `WESTFUND\\` → bare username).

Filter rows to the requested date range by comparing `str(row['Session Start'])[:7]` (for month) or the full date prefix.

```python
import openpyxl
from collections import defaultdict

wb = openpyxl.load_workbook('/mnt/user-data/uploads/<filename>.xlsx')
ws = wb.active
rows = list(ws.iter_rows(values_only=True))[1:]  # skip header
```

### 2. Determine time buckets

**Month breakdown** — bucket key = `str(date)[:7]`, e.g. `"2026-02"`. Label as `"2026年2月"`.

**Week breakdown** — the user provides explicit date ranges. Map each row's day-of-month to the correct bucket:

```python
def get_week(date_str, week_ranges):
    # week_ranges = [(start_day, end_day, label), ...]
    day = int(str(date_str)[8:10])
    for start, end, label in week_ranges:
        if start <= day <= end:
            return label
    return None
```

**Day breakdown** — bucket key = `str(date)[:10]`, e.g. `"2026-02-05"`. Label as `"02/05"`.

### 3. Aggregate counts

Build a dict: `user → {bucket_label → session_count}`.

Sort users by total session count descending.

Compute column totals for the footer row.

### 4. Generate the HTML

Write a single self-contained `.html` file to `/mnt/user-data/outputs/`. Use Chart.js from cdnjs:

```
https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js
```

#### Table structure

```
| 用户 | Bucket1 | Bucket2 | ... | 趋势 | 合计 |
```

- Zero values display as `—` in muted grey (`color: #ccc`).
- The **趋势** column contains a `<canvas>` element (110×40px) per row — rendered as a sparkline.
- Footer row shows column totals.

#### Sparkline colour coding

Colour each sparkline based on the trend shape of that user's data:

```python
def get_color(values):
    if not any(values): return '#aaa'
    peak_idx = values.index(max(values))
    if peak_idx == len(values) - 1: return '#4ecf8e'   # rising  → green
    if peak_idx == 0:               return '#e05c5c'   # falling → red
    if peak_idx == len(values) // 2: return '#f7a94e'  # peak middle → orange
    return '#4e8ef7'                                    # other → blue
```

#### Chart.js sparkline config (per canvas)

```javascript
new Chart(canvas, {
  type: 'line',
  data: {
    labels: bucketLabels,
    datasets: [{
      data: userValues,
      borderColor: color,
      backgroundColor: color + '33',
      pointBackgroundColor: color,
      pointRadius: 3,
      borderWidth: 2,
      fill: true,
      tension: 0.3,
    }]
  },
  options: {
    animation: false,
    responsive: false,
    plugins: { legend: { display: false } },
    scales: {
      x: { display: false },
      y: { display: false, beginAtZero: true }
    }
  }
});
```

Use `requestAnimationFrame` when rendering sparklines after DOM insertion to ensure the canvas is mounted.

#### Styling

```css
body        { font-family: 'Segoe UI', Arial, sans-serif; background: #f5f7fa; padding: 24px; }
table       { width: 100%; border-collapse: collapse; background: white; border-radius: 8px;
              box-shadow: 0 2px 8px rgba(0,0,0,0.08); overflow: hidden; }
thead tr    { background: #1a3c6e; color: white; }
th, td      { padding: 10px 16px; text-align: center; font-size: 13px; border-bottom: 1px solid #f0f0f0; }
th:first-child, td:first-child { text-align: left; }
td:first-child  { font-weight: 500; color: #1a3c6e; }
tr:hover td { background: #f0f4ff; }
tfoot tr    { background: #f0f4ff; font-weight: 700; }
tfoot td    { border-top: 2px solid #1a3c6e; }
.zero       { color: #ccc; }
.total-col  { font-weight: 700; }
.spark-cell { width: 120px; padding: 4px 12px; }
```

#### Page header

Include:
- `<h2>` with app name and date range
- `<p class="subtitle">` with granularity description, e.g. `W1: 02–08/02 | W2: 09–15/02 | W3: 16–22/02`
- A colour legend row (rising / falling / peak-middle / other) using small coloured squares

### 5. Output

Save the file to `/mnt/user-data/outputs/<descriptive_name>.html` and present it with `present_files`.

---

## Behaviour Notes

- **Strip domain prefix** from all usernames before display (`WESTFUND\\` → plain name).
- **"Other" buckets** (dates outside all defined week ranges) are silently ignored — do not include them in totals or display.
- **All users vs filtered**: Default to showing all users in the date range unless the user asks for a filter (e.g. "only users active in all months").
- **Day breakdown with many days**: If there are more than ~20 day columns, reduce the sparkline canvas width to 180px and allow horizontal table scrolling (`overflow-x: auto` on a wrapper div).
- **Missing columns**: If `CPU Spent`, `KB Transferred` etc. are absent from the file, skip those — only `Session Start` and `User ID` are required.
- **Updating data**: When the user says "I have updated data", re-read the new upload file and regenerate the HTML from scratch using the same granularity and date range as before, unless told otherwise.

---

## Example Trigger Prompts

- "帮我做一个2月份用户会话按周细分的图表" (week breakdown)
- "针对12月到2月，按月统计用户会话，每行给一个sparkline"
- "我更新了数据，重新生成一下"
- "把粒度改成按天"
