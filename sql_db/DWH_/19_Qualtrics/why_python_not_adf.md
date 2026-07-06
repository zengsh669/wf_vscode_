# 为什么用 Python (Notebook) 而不是 ADF 来抓取 Qualtrics 数据
# Why Python (Notebook) Instead of ADF for Qualtrics Data Extraction

## 1. 数据格式问题（最根本的原因）
## 1. File Format Issue (the root cause)

Qualtrics 的自由文本评论字段里，用户填写内容有时会包含真实换行符——这在 CSV 标准（RFC 4180）里是合法的（换行符被双引号包裹），但 ADF 的 Copy Activity（DelimitedText 连接器）无法正确处理"引号内换行符不算断行"这个规则，会把一条记录错误拆成两行，导致列数不匹配、任务报错（`DelimitedTextMoreColumnsThanDefined`）。

Sometimes when people fill in comments on the Qualtrics surveys, they hit enter and the text wraps onto a new line. That's legal under the CSV standard (RFC 4180) when wrapped in quotes, but ADF's Copy Activity (DelimitedText connector) misreads it as a new row, which splits one response into two and makes the whole job fail with a column-count mismatch error (`DelimitedTextMoreColumnsThanDefined`).

**已经实测验证**：小份问卷（MentalHealth 4行、HealthServices 18行等）刚好没踩到这个问题，能跑通；但 CSAT（39,000+行）稳定复现这个报错。这是 ADF 该连接器的已知限制，不是配置问题——要修复需要引入更复杂的 Mapping Data Flow，或者干脆调用 Python 来处理，绕一圈还是离不开 Python，不如直接用。

**Tested and confirmed**: small surveys (MentalHealth with 4 rows, HealthServices with 18 rows) happen to avoid this issue and run fine, but CSAT (39,000+ rows) reliably reproduces the error. This is a known limitation of that ADF connector, not a configuration mistake — fixing it in ADF would require a more complex Mapping Data Flow, or calling out to Python anyway. Since that ends up needing Python either way, it's simpler to just use Python from the start.

Python 的 `pandas.read_csv()` 天然正确处理这种情况，已经在 notebook 里验证过全部6份问卷都能完整、无损地解析。

Python's `pandas.read_csv()` handles this correctly out of the box — already verified in the notebook that all 6 surveys parse completely and without data loss.

## 2. Qualtrics 数据本身不是"标准"结构化数据
## 2. Qualtrics Data Isn't "Clean" Structured Data

It looks like a table, but underneath it's messy:
表面上看是表格，但底层内容其实很不规则：

- 每份问卷的字段编号（`Q2`/`Q7` 等）不统一，没有固定规律
  Every survey uses different, inconsistent question codes
- 编号还会随问卷被编辑而漂移——已经实测发现：MentalHealth 的 Qlik 脚本注释写的是 `QID15`（Satisfaction），实际 API 返回却是 `Q7`；WellbeingV2 也出现过类似的题号对不上的情况
  Those codes can drift whenever a survey is edited — we already found cases where the old documentation doesn't match what the system returns today (e.g. MentalHealth's Qlik script comments say `QID15` for Satisfaction, but the real API export uses `Q7`)
- 大量自由文本评论，内容完全不受控，可能包含各种特殊字符
  There's a lot of free-text comments in there, which can contain all sorts of characters

这种"字段不固定、会漂移"的半结构化数据，用代码处理更灵活——改一行代码就能适应变化；ADF 那种图形化配置，字段一变就要重新点好几个不同的界面。

This kind of data — where the fields aren't fixed and can shift — is easier to handle with code, since a change is just a one-line fix. ADF would need several settings updated across different screens whenever a field changes.

## 3. 管理与可读性
## 3. Manageability and Readability

6份问卷的抓取逻辑，Python 全部写在同一个文件里——一个字典 (`SURVEYS`) + 一个循环就能覆盖全部6份，加一份新问卷只要加一行。

All 6 surveys are handled in a single Python file — one dictionary (`SURVEYS`) plus one loop covers all of them, and adding a 7th survey is a one-line addition.

ADF 每接入一份新问卷，都要重新配置好几个不同的界面（改3处 Survey ID：StartExport、CheckStatus、Source Dataset；建新的 Sink Dataset；有时还要新建 Linked Service）——逻辑分散在多个 UI 面板里，不容易一眼看清全貌，也更容易漏改、出错。

With ADF, every new survey means reconfiguring several different screens (Survey ID in 3 separate places — StartExport, CheckStatus, Source Dataset; a new Sink dataset; sometimes a new Linked Service) — the settings are scattered across multiple UI panels, harder to review at a glance, and easier to make an inconsistent change.

## 结论
## Conclusion

三类原因加在一起——**ADF 有已知的解析限制（无法正确处理引号内换行符）、Qualtrics 数据本身字段不稳定会漂移、以及 Python 在多问卷场景下更易于统一管理**——共同决定了这次 Qualtrics 数据抓取选择用 Python/Notebook 实现，而不是 ADF Pipeline。

Taken together — ADF's known parsing limitation (it can't correctly handle line breaks inside quoted fields), Qualtrics' inherently unstable/drifting field structure, and Python's easier unified management across multiple surveys — these three reasons are why this Qualtrics data extraction was built in Python/Notebook rather than as an ADF Pipeline.

## 待确认：定时调度方案与 WFOnPremise
## Open Question: Scheduling Approach and WFOnPremise

现有的数据仓库更新模式是：ADF Trigger 定时触发 Pipeline，Pipeline 调用本地 SQL Server 的 Stored Procedure 做 Type 1（全量覆盖）更新。但这个 notebook 的转换逻辑用的是纯 Python/pandas，数据源头是外部 Qualtrics REST API，不在 SQL Server 里，SP 无法主动调用外部 API，所以现有模式没法直接套用。

The existing data warehouse refresh pattern is: an ADF Trigger fires a Pipeline on a schedule, which calls a Stored Procedure on the local SQL Server to do a Type 1 (full overwrite) update. But this notebook's transformation logic is pure Python/pandas, and its data source is the external Qualtrics REST API — not something already sitting in SQL Server — so a Stored Procedure has no way to reach out and call an external API. The existing pattern doesn't directly apply here.

在 ADF 里发现有一个名为 `WFOnPremise` 的 Self-hosted Integration Runtime，目前用于连接内网的 SQL Server（如 `prdsql05`）。这说明公司确实有一台内网常开的机器在跑基础设施相关服务，可能是之前讨论调度方案时提到的"常开内网服务器"的候选。但从"能连 SQL Server"到"能定时跑 Python notebook"，还有几个问题需要向 IT 确认：

In ADF, there's a Self-hosted Integration Runtime named `WFOnPremise`, currently used to connect to internal SQL Server instances (e.g. `prdsql05`). This confirms there is an always-on internal machine running infrastructure-related services — possibly the "always-on internal server" candidate discussed earlier when considering scheduling options. But there's a gap between "can connect to SQL Server" and "can run a scheduled Python notebook," and a few things need to be confirmed with IT:

1. `WFOnPremise` 具体装在哪台机器上？是独立的专用服务器/VM，还是装在某个团队现有服务器上的一个服务？
   Which machine is `WFOnPremise` actually installed on? Is it a dedicated standalone server/VM, or a service installed on some team's existing server?
2. 这台机器能不能额外安装 Python 环境、跑定时任务（Task Scheduler）？是否有变更管控限制？
   Can that machine have a Python environment installed and run scheduled tasks (Task Scheduler)? Are there change-management restrictions?
3. 这台机器的网络出站规则是否允许访问外网的 Qualtrics API（`syd1.qualtrics.com`），还是只白名单开放了内网地址？
   Does that machine's outbound network policy allow reaching the external Qualtrics API (`syd1.qualtrics.com`), or is it locked down to an internal-only allowlist?
4. 这台机器能不能访问共享盘 `\\prdeqs01\QlikData\Qualtrics`（如果最终用这台机器做定时导出）？
   Can that machine reach the shared drive `\\prdeqs01\QlikData\Qualtrics` (if this machine ends up being used for the scheduled export)?

这几点确认清楚后，才能最终决定 notebook 的定时调度方案。

Once these are confirmed, a final decision can be made on the notebook's scheduling approach.
