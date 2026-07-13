# Qualtrics 数据接入 — 进度记录

最后更新：2026-07-13

## 目标

把 Qlik 里现有的 Qualtrics NPS/满意度调查数据加载逻辑迁移到 Python/SQL Server。

**目标经历过一次范围调整，以下是最新状态（2026-07-13）**：最初的核心目标是"用
`qualtrics_fetch.ipynb` 复刻 `Qualtrics_NPS_Score.md` 里的 `NPS_Score` 合并逻辑"（详见下方
"关键发现"一节，此目标本身没有变化，验证已完成）。但**落地到生产部署时**，范围被进一步拆分：
正式部署脚本 `qualtrics_fetch.py`（`DataEngineering/QualtricsData/`，独立 ADO 仓库）**只负责
6 份问卷各自抓取写入 `BRONZE.qua.*`**，`NPS_Score` 的合并改为交给 SQL Server 端 Stored Procedure
处理（尚未编写）——即最初"用 Python 完整复刻 NPS_Score"的目标，现在拆成"Python 管抓取、SQL
管合并"两段。详见下方"部署路径确定与验证"及"`qualtrics_fetch.py`：正式抓取脚本落地"两节。

ADF Pipeline 的探索作为并行/备选路径保留，但因遇到 CSV 解析限制，目前主线转向纯 Python 方案。

**本文档涉及的几份关键代码文件，容易因命名相似而混淆，先在此做区分**：
- `qualtrics_data_extract_fetch.ipynb`（`sql_db/DWH_/19_Qualtrics/`）—— 全字段复刻版 notebook，
  复刻 `Qualtrics_Data_Extract.md` 的完整逻辑，经 round 5-13 多轮审查验证，是目前**逻辑层面的
  权威版本**
- `qualtrics_fetch.ipynb`（`sql_db/DWH_/19_Qualtrics/`）—— 简化版 notebook，只做 `NPS_Score`
  合并逻辑的复刻，本文档最早的产出
- `qualtrics_fetch.py`（`DataEngineering/QualtricsData/`，**注意文件名与上面的 `.ipynb` 几乎相同
  但不是同一份东西**）—— 这次新增的**正式部署脚本**，其抓取+转换逻辑搬运自
  `qualtrics_data_extract_fetch.ipynb`（全字段版），不是 `qualtrics_fetch.ipynb`（简化版）

## 关键发现：三份 Qlik/文档之间的关系

项目文件夹下有3份关键源文档，理清了完整的数据血缘：

1. **`Qualtrics_Data_Extract.md`**（真正的 ETL 源头）——直连 Qualtrics API（`LIB CONNECT TO 'Qualtrics'`），对 6 份问卷做字段重命名（含 Provider/Branch 映射，依赖 Paragon BRONZE 表 + `BranchLocations.xlsx`），各自存成 QVD；同时也是 `NPS_Score`/`DataforBI`/`DataforScreen`/`DataforHCS_NPS_Calcs` 这几个下游转换**当前实际生效**的地方（2026-06-30 从 `Qualtrics_NPS_Score` App 迁移过来，注释："transforms should not be done in presentation Apps"）。
2. **`Qualtrics_NPS_Score.md`**（展示层 App，逻辑已退化）——目前**唯一生效**的代码只有 6份QVD `CONCATENATE` 成 `NPS_Score`（过滤 `Member Number` 非空）；`DataforBI`/`DataforScreen`/`DataforHCS_NPS_Calcs` 三段全部被 `/* */` 注释掉，是死代码。
3. **`qualtrics_fetch.ipynb`**——本次工作的主要产出，绕开 Qlik，直接调 Qualtrics REST API 复刻上述 `NPS_Score` 合并逻辑。

三份文档已原样存档在本目录（`Qualtrics_Data_Extract.md`、`Qualtrics_NPS_Score.md`），供比对。

## 涉及的 6 份 Qualtrics 源问卷

**注：下表行数是 2026-07-03 那次抓取的快照。下方"`qualtrics_fetch.py`：正式抓取脚本落地"一节
（2026-07-13）有另一份行数更新的表格——两者数字不同属正常（Qualtrics 问卷持续有新回复进来），
不代表数据矛盾或错误，只是不同时间点各自的抓取结果。**

| 问卷 | Survey ID | 原始行数 | 有 Member Number 行数 |
|---|---|---|---|
| Customer Satisfaction Survey (CSAT) | `SV_eXLP1SmIM6zjdXv` | 39,047 | 38,988 |
| POC Survey | `SV_9GjRYiNTNKsuKkR` | 9,058 | 9,058 |
| Health Services | `SV_1Yx80MMG0nDHTAF` | 18 | 18 |
| Mental Health Program | `SV_2hm4kwhNudIHB2t` | 4 | 1 |
| Health and Wellbeing Program | `SV_6m5bFDluaJjxO8R` | 25 | 25 |
| HCS NPS Questionnaire (Wellbeing V2) | `SV_efX6mORlYWtebXg` | 330 | 328 |

**`NPS_Score` 合计 48,418 行**，对比 Qlik App 实际运行结果 48,415 行，差 3 行（0.006%），判定为拉取时间点不同导致的新增数据，可接受。

第6份问卷（Wellbeing V2 / HCS NPS Questionnaire）是 2025-12 才由 Monique Rust 新增，之前的 progress 记录遗漏了它，本轮已补全。另有3个 Survey ID 在 Qlik `vSurveys` 列表出现但无对应 `STORE...qvd`，确认不在范围内。

## `qualtrics_fetch.ipynb` 完成情况

**已验证跑通并 100% 复刻 `Qualtrics_NPS_Score.md` 的生效逻辑**（子代理独立核对确认：问卷覆盖、过滤语义、合并顺序、6份问卷各自字段映射均一致）：

- `fetch_survey_responses()` — 发起导出→轮询→下载解压→读CSV，支持任意 Survey ID
- `fetch_question_definitions()` — 调用 Qualtrics `survey-definitions` API，拿到题目原文+真实导出字段名，替代"猜字段名"（详见下方"字段映射验证"）
- 6个 `standardise_*()` 函数 + `STANDARDISERS` 字典 — 逐份问卷标准化列名
- `NPS_Score` 构建 — 逐份过滤 Member Number 非空 → concat，跟 Qlik 的"先过滤再CONCATENATE"顺序一致
- `DataforScreen`（对应 `NPS_Display.qvd`）— 额外做的扩展，精确复刻近5财年过滤（`MakeDate(Year(AddYears(today(),-5)),7,1)`）+ 4个字段重命名。**注：这部分不属于 `Qualtrics_NPS_Score.md` 的必需范围**（该 App 里这段逻辑已被注释废弃，现属于 `Qualtrics_Data_Extract.md` 的范畴），是主动扩展。

### 字段映射验证状态（6份问卷）

**注：下表已过时，保留仅作历史参照。CSAT 的 Satisfaction 字段当时写的 `Q10` 实际是本轮
（2026-07-03）发现的 bug 本身，不是验证结果——`Q10` 在真实导出里根本不存在。最新、
经真实 CSV + ImportId 核实的准确状态见下方"round 12-13"章节。**

| 问卷 | NPS字段 | Satisfaction字段 | 验证方式 |
|---|---|---|---|
| CSAT | Q2/Q2_NPS_GROUP | Q10/Q10_NPS_GROUP | 与实际列名核对 |
| POC | Q6/Q6_NPS_GROUP | Q4/Q4_NPS_GROUP | 与实际列名核对 |
| HealthServices | Q2/Q2_NPS_GROUP | （无此字段，Qlik原脚本也没有） | 与实际列名核对 |
| MentalHealth | Q3/Q3_NPS_GROUP | Q7/Q7_NPS_GROUP | ✅ **已用 survey-definitions API 题目原文 + 数值分布双重验证**（Q3="On a scale 0-10 how likely to recommend MindStep"；Q7="Overall how satisfied were you with the program" — 均确认正确） |
| Wellbeing (非V2) | Q3/Q3_NPS_GROUP | Q8/Q8_NPS_GROUP | ⚠️ 未做题目原文验证，仅照抄其他问卷规律推断，风险低（不影响"复刻md"目标，只影响该问卷内容语义精确性） |
| WellbeingV2 | Q3/Q3_NPS_GROUP | Q4/Q4_NPS_GROUP | ✅ 已用 survey-definitions API + 数值分布验证 |

**重要教训**：Qlik 脚本里的 `QID` 编号（如 `QID15`）**不可靠**，实际 API 导出字段名（`Q7`）经常对不上——这是因为 Qlik 内置连接器用的是 Qualtrics 内部 QuestionID，REST API 导出用的是另一套编号，且问卷被编辑后编号会漂移。已发现的实例：MentalHealth 的 Satisfaction，Qlik 注释写 `QID15`，实际是 `Q7`。**已建立 `fetch_question_definitions()` 作为可靠的验证手段**，之后遇到新问卷/新字段应优先用这个核实，不要直接照抄 Qlik 脚本注释。

**关键区分——Qlik App 本身依然可信，问题出在 Python 实现方式，不是 Qlik 的问题**：Qlik 内置的
Qualtrics 连接器不是靠脚本里写死的 `QIDnn` 字符串去匹配列名的，它是真正的动态连接器——每次
Qlik App 刷新时，都会重新向 Qualtrics 系统查询"`QIDnn` 现在对应哪个真实导出字段"，然后动态
解析出正确数据，所以 Qlik App 每次运行都会自动对齐当前状态，不会有漂移问题。我们的 notebook
之所以会漂移，是因为它直接调用 Qualtrics REST API 的 `export-responses` 接口，这个接口返回的
CSV 列名本身就是当次导出的 `Qnn`（不含 `QIDnn` 这个"永久身份证号"信息），所以只能把 Qlik 脚本
文字里当年写下的 `QIDnn`→`Qnn` 对应关系当作静态字符串硬编码进 Python 代码——这一步把 Qlik
连接器原本"动态解析"的能力，退化成了"写死的快照"，快照会过期，但 Qlik App 本身不会。这也是
为什么很难把 notebook 做成完全动态/自动免疫漂移的（详见下方"关于让字段映射完全动态化"）：
Qualtrics 的 `export-responses` 接口本身不支持"按 QuestionID 导出"，只能按 `Qnn` 导出，这是
REST API 这条路径的根本限制，不是实现疏忽。

### 已发现并修复的 bug

`standardise_*()` 函数里最初直接用 `out["Survey_id"] = SURVEYS["CSAT"]` 这种标量赋值给全新 DataFrame 的列，pandas 不会正确广播，导致 `Survey_id`/`SurveyName` 两列全部变成 NaN（不是显示问题，是真实数据丢失）。已修复：新增 `constant_col(value, df)` 辅助函数，用 `pd.Series([value]*len(df), index=df.index)` 显式构造，`out = pd.DataFrame()` 也改为 `out = pd.DataFrame(index=df.index)` 先固定索引。修复后重新验证，两列数据正确对齐无 NaN。

### 已知的、明确排除的范围

- **Provider/Branch 映射字段**（`ProviderType`/`ProviderAddress`/`ProviderSuburb`/`ProviderState`/`ProviderPostcode`）—— 依赖 Paragon BRONZE 表（`Paragon_Provider.qvd`/`Paragon_ProviderNumber.qvd`/`Paragon_Provider_Type.qvd`）和 `BranchLocations.xlsx` 做 `ApplyMap` 查找，用户明确要求本次范围排除，字段留空（NaN）。
- **`DataforBI`**（CSAT专属Eye Care/Dental过滤，产出 `QualtricsSurveyData.csv`）—— 未复刻，非必需范围。
- **`DataforHCS_NPS_Calcs`**（多 Feedback/Feedback Improvements/Program Type 三个自由文本字段，产出 `Qualtrics_NPS_HCS_Data.qvd`）—— 未复刻，非必需范围。这两项如果之后要做，需要先在每份 `standardise_*()` 里补上对应问卷的 Feedback 类字段提取（各问卷字段名不同，需要逐一核实，不能照抄）。

## 为什么选 Python/Notebook 而非 ADF

已写入独立文档 [why_python_not_adf.md](why_python_not_adf.md)（中英对照），核心三点：
1. ADF 的 Copy Activity 无法正确处理评论字段内嵌换行符（RFC 4180 引号内换行），在 CSAT（39,047行）上稳定复现解析报错；MentalHealth 等小数据集能跑通只是侥幸未触发，不代表问题已解决
2. Qualtrics 数据字段编号不统一且会随问卷编辑漂移，代码处理比 ADF 图形化配置更灵活
3. Python 把6份问卷逻辑集中在一个文件里，比 ADF 每份问卷要重新配置多个界面更易管理

## 部署路径确定与验证（2026-07-13）

调度方案已从"待定"推进为**确定并部分验证成功**：

- **Azure Function App 路径受阻**：尝试在 Azure Portal 创建 Function App（Flex Consumption 计划）时，
  卡在需要注册 `Microsoft.App` 资源提供程序这一步，账号权限不足（`AuthorizationFailed`），且无法
  自行创建 Resource Group。此路径搁置。
- **确定改用：VM（IR Machine）+ Windows Task Scheduler**。VSCode/本地账号对 SQL Server 仅有只读权限，
  只有 Integration Runtime 机器的身份被确认有写入可能，由 IT（Trev）负责该机器的环境与调度配置。
- **建立独立的 ADO 仓库 `DataEngineering`**（Azure DevOps，与本仓库 `wf_vscode_` 完全独立，remote
  分别指向 GitHub 与 ADO）。已配置 CI Pipeline（`azure-pipelines.yml`）：push 到 `main` 自动打包成
  Artifact，验证正常运作。原负责"打包产物→VM"这一步的 `copy.ps1`，一度确认从未被任何流程实际
  调用，后由 Trev 删除（commit "remove not required files"）——目前 ADO Artifact 到 VM 的落地机制
  待 Trev 确认（可能已改用 Release Pipeline 网页配置，或其他方式）。
- **`write_test.py`（`DataEngineering/QualtricsData/`）** ——独立于 Qualtrics API 的最小化 SQL Server
  写入测试脚本，用于单独验证"这台机器的身份能否写入 SQL Server"这一根本问题。经 3 轮子代理
  独立审查 + 用户本人审查，修复以下 4 处 bug：
  1. `ensure_table_exists()` 建表后调用了 `cursor.commit()`——pyodbc 的 `Cursor` 对象没有
     `.commit()` 方法，只有 `Connection` 有；改为 `conn.commit()`，函数签名相应从
     `(cursor, table_name)` 改为 `(conn, cursor, table_name)`。
  2. 一处注释引用了已被用户要求删除的旧文件 `qualtrics_poc_ir_test.py`（早期的完整 POC 抓取
     版本，后按用户指示删除，改用当前简化的手写 3 行测试数据方案）——改写为直接描述做法本身，
     不再引用已不存在的文件。
  3. `write_to_sql_server()` 原本没有 `try/finally`，如果建表/写入中途报错（例如实际遇到的
     `CREATE TABLE permission denied`），`cursor.close()`/`conn.close()` 永远不会执行，导致
     连接泄漏——尤其不可接受，因为脚本以后会被 Task Scheduler 反复无人值守调用。已改为把
     连接相关操作包进 `try`，`conn.close()` 移入 `finally`。
  4. `main()` 里 `write_log_file()` 本身没有异常保护——如果写日志这一步失败（只读共享文件夹、
     磁盘满等），会抛出一个未被捕获的异常，导致"作为唯一诊断依据的 JSON 日志"这个设计目的
     直接落空。已包一层 `try/except`，失败时改为把 traceback 打印到 stderr 作为兜底，
     并通过 `_error_detected_local` 变量正确设置最终的成功/失败判定。

  另有 2 处子代理提出但经用户判断为低优先级、明确决定不修的建议（`_error_detected_local`
  变量作用域的防御性写法、`cursor.close()`的冗余调用），均评估过实际影响可忽略。

  完成以上修复后：
  - 本机测试：连接成功，但在 `CREATE TABLE` 时被拒绝（`permission denied in database 'BRONZE'.
    (262)`）——确认本地账号无写入权限，属预期结果。
  - **VM 端测试：写入成功**（`BRONZE.dbo.Qualtrics_Write_Test`，3 行测试数据可查询确认）——首次
    确认 VM 身份具备 SQL Server 写入/建表权限，此前悬而未决的核心阻塞点已解决。
- **ODBC 驱动版本差异**：本机装的是 `ODBC Driver 17`，VM 端为 `ODBC Driver 18`（Trev 已将 `write_test.py`
  对应版本改为 18，commit "update driver reference to 18"）。`qualtrics_fetch.py`（见下）连接字符串
  按 VM 环境使用 18；本机运行时会在建立连接阶段报 `IM002 Data source name not found`，属预期内的
  环境差异，不代表代码问题。
- **VM 系统时区尚未确认**——`datetime.now()` 写入的时间戳（如 `InsertedAt`）依赖 VM 操作系统本身
  设置的时区，代码本身不做任何时区转换，需另行向 Trev 确认是悉尼时间还是 UTC。

## `qualtrics_fetch.py`：正式抓取脚本落地（2026-07-13）

在 `write_test.py` 验证的骨架基础上，正式编写了 Qualtrics 6 份问卷的抓取脚本：
`DataEngineering/QualtricsData/qualtrics_fetch.py`（独立于本仓库，由 ADO 仓库 `DataEngineering`
追踪，已 commit + push）。

**范围界定**：本脚本只负责 6 份问卷各自的抓取、标准化、写入 `BRONZE.qua.*`（`Qualtrics_CSAT` /
`Qualtrics_POC` / `Qualtrics_HealthServices` / `Qualtrics_MentalHealth` / `Qualtrics_Wellbeing` /
`Qualtrics_Wellbeing_V2`，schema 为 `qua`）。**`NPS_Score` 的合并逻辑不在本脚本中实现**——按决定
改为由 SQL Server 端 Stored Procedure 读取这 6 张表做 `UNION ALL` + 过滤，SP 尚未编写。

**逻辑来源**：直接搬运 `qualtrics_data_extract_fetch.ipynb` 的 6 个 `standardise_*_full()` 函数、
全部共享 helper 函数（`notnull_or_blank`/`blank_to_null`/`multiselect_join` 等）与硬编码映射表
（`PROGRAM_PROVIDER_ID_MAP` 等），经子代理逐行核对确认**零差异**（含全部 "Round N fix" 修正过的
字段）。

**基础设施**（继承自 `write_test.py`，非本次新增设计）：JSON 日志（存于独立的 `logs/` 子文件夹，
调用时自动创建）、`try/finally` 连接清理、单一 survey 失败不影响其余 5 份继续处理、日志写入本身
的容错兜底。查询问卷最新名称（`Survey Name`）的 API 调用失败时会自动降级使用硬编码的
`SURVEY_NAMES`，不阻断整体流程——这是本次新增的容错设计，notebook 原逻辑没有这一层（无
容错，失败即报错），属于"无人值守定时执行"场景下的主动补强，非复刻遗漏。

**真实数据验证**（本机执行，2026-07-13）：6 份问卷全部成功抓取 + 标准化。**下表行数是这次
（2026-07-13）的抓取快照，与上方"涉及的 6 份 Qualtrics 源问卷"一节的 2026-07-03 数字不同，
属正常的数据增长，不是矛盾**：

| 问卷 | 抓取行数 | 标准化后列数 |
|---|---|---|
| CSAT | 39,152 | 37 |
| POC | 9,080 | 39 |
| HealthServices | 18 | 36 |
| MentalHealth | 4 | 36 |
| Wellbeing | 25 | 37 |
| WellbeingV2 | 330 | 35 |

列数与子代理审查 notebook 时确认的数字完全一致。写入 SQL Server 这一步因本机 ODBC 驱动版本
（17）与代码指定版本（18）不匹配，在建立连接阶段即失败（`IM002`），未能在本机验证到"写入"
这一步——预期内的环境差异，非代码缺陷，待 VM 端（已确认装 18）实际测试。

**API Token**：延续本仓库既有决定，先明文硬编码在代码中以便验证跑通，环境变量化仍在长期待办中。

## ADF Pipeline 探索记录（备选路径，非当前主线）

Pipeline 名称：`Qualtrics`，流程：`StartExport`→`PollExport`(Until循环)→`DownloadAndUnzip`→`UnzipToCsv`→`CsvToSqlServer`。已验证 MentalHealth 这一份能完整跑通并写入 BRONZE（`qua.Qualtrics_Dental_NPS_Raw`，因跳过表头列名为 `Column_1,2...`）。CSAT/POC 因上述 CSV 解析问题未能接入。详细组件配置、报错分析见本文件历史版本（git log 或询问助手）。此路径按需可继续，但当前工作重心已转向 Python notebook。

**API Token** 目前明文写在 notebook 和 ADF Linked Service 里，未接入 Key Vault/环境变量（用户决定「先不处理，之后再说」）。

## `qualtrics_data_extract_fetch.ipynb`（全字段复刻版）round 5 复核发现

第5轮独立复核对 `qualtrics_data_extract_fetch.ipynb`（复刻 `Qualtrics_Data_Extract.md` 全字段版本，非本 `qualtrics_fetch.ipynb` 的简化 `NPS_Score` 版本）做了逐字段交叉核对，发现并修复一处同类 QID→Q 编号误转换 bug：

- **WellbeingV2 `[Program Type]`**：该 notebook 之前照抄 Qlik `QID21` 注释（"Which Service"）写成 `Q21`。但本 notebook（`qualtrics_fetch.ipynb`）的 `standardise_wellbeing_v2` 里已有明确注释（两处）指出，经 `survey-definitions` API 题目原文核实，"Which service did you receive?" 的真实导出字段是 `Q2`，不是 `Q21`——`Q21` 从未被独立验证过对应这个含义。已在对方 notebook 里改为 `Q2`（保留原有 blank-fallback-to-`Survey` 结构不变）。
- 其余字段（CSAT/POC/HealthServices 的非NPS/Satisfaction字段、MentalHealth/WellbeingV2 已修复字段以外的字段、Wellbeing 的 Q4/Q13/Q15/Q6_TEXT）经交叉核对与本 notebook 一致或本 notebook未覆盖（超出 `NPS_Score`/`COMMON_COLUMNS` 范围，无法交叉验证），未发现新问题。
- Wellbeing（非V2）的 `Q3`/`Q8` 映射本轮仍未获得新的 API 验证证据，维持 pattern-inferred 状态。

## `qualtrics_data_extract_fetch.ipynb` round 7 复核发现

第7轮独立复核（本轮为"决定轮"——若本轮也 clean 则停止迭代）重点不再是逐个 Q 编号复查（round 6 已穷尽），而是抽查 round 6 分类是否准确、检查 Q 编号以外的字段、结构性问题，并做新边界情况的执行测试。

- **抽查 round 6 的 tier-(c) 分类**：独立重新核对 POC（Q2/Q3/Q5_TEXT/Q7_TEXT）、HealthServices（Q3/Q3_6_TEXT/Q24/Q9_TEXT/Q18_TEXT）against `Qualtrics_Data_Extract.md` 原始注释块，round 6 分类保持准确——这些字段确实只能依赖 Qlik 自身注释、无法在无 API 权限下进一步验证。
- **发现并修复一个新 bug（非 Q 编号类）**：`[Provider Group]` 字段（HealthServices/MentalHealth/Wellbeing/WellbeingV2 四份问卷，经 `ApplyMap('ProgramProvider_Map', ProviderNo)`）——`ProgramProvider_Map` 是硬编码 inline table（`Qualtrics_Data_Extract.md` 68-75行），**不依赖 Paragon BRONZE**，理应在本 notebook 范围内复刻。但发现代码里 `program_provider_group()`/`PROGRAM_PROVIDER_MAP` 这两个 helper 已经在共享 helper cell 里写好（且注释声称"已修复为像 ProviderNo 一样被复刻"），却**从未被实际调用**——4份问卷的 `standardise_*_full()` 函数里都没有 `out["Provider Group"] = ...` 这一行，导致该列静默缺失。同时 notebook 顶部 markdown 文档仍写着这4份问卷的 Provider Group 被排除在范围外，与 helper cell 注释自相矛盾。已在4处 `standardise_*_full()` 函数里补上 `out["Provider Group"] = program_provider_group(out["ProviderNo"])`，并更新顶部 markdown + HealthServices 段落 markdown 消除矛盾表述。
- **确认此前遗留的 round-7（中断重试前）已应用修复**：`Qualtrics_Questions` 此前只循环 `SURVEYS`（6份问卷）取题目定义，但 Qlik 的 `For Each vSurveyID IN $(vSurveys)` 循环覆盖全部8个 Survey ID（含2个从未有对应 response QVD 的"90 Day NPS"/"10 Day NPS - New member survey"）——已改为 `ALL_VSURVEYS`（8个ID）覆盖，与 Qlik 脚本行为一致。本轮验证此修复逻辑正确（对照 .md 41行 `vSurveys` 变量 + 254行循环 + 仅6个 `STORE Qualtrics_*.qvd` 语句，确认8个ID中确实只有6个有独立 response QVD）。
- **执行测试**：复制全部 helper 函数 + `standardise_csat_full`/`standardise_healthservices_full` 到独立脚本，跑通以下边界情况：全字段同时为 NaN 的行、`Duration`为空白字符串、NPS_GROUP字段为纯空白字符串、`StartDate`本身为NaN、`_split_timestamp`对None/空字符串/畸形字符串/ISO字符串的处理、前后有空白但非空的Q编号字段值（应保留原值，符合Qlik `Len(Trim(x))=0` 语义只在"纯空白"时才转null，不对非空值做trim）——全部通过。另测试了重复列名这一理论边界情况：`notnull_or_blank()`在DataFrame出现重复列名时会返回DataFrame而非Series，属于潜在脆弱点，但Qualtrics CSV导出实际不会产生重复列名，非真实风险，未作修复。
- **markdown 一致性检查**：除上述 Provider Group 矛盾（已修复）外，其余各问卷 markdown header 与其下方代码逻辑一致，无其他 stale 注释。
- **非Q编号字段交叉污染检查**：Status/IPAddress/Duration/Recipient/ExternalReference/Age/Gender/Postcode/State/Region/TenureMonths/PreviousFund/Promotion/ClaimNo/Agreement/Operator/Relationship/Member Number 等字段逐一核对，均正确来自各自问卷的对应源列，无跨问卷混用。

## `qualtrics_data_extract_fetch.ipynb` round 10-13 复核发现（2026-07-03）

这一批复核首次引入了"真实数据"验证手段——不再仅依赖 `survey-definitions` API 的题目文本，
而是实际发起真实 `export-responses` 导出（触发→轮询→下载→解压 CSV），用 CSV 第2行的
`ImportId` 元数据（Qualtrics 官方写的、`Qnn`↔`QIDnn` 的权威对照）逐字段核对。这是迄今为止
证据链最扎实的一轮，发现了之前"仅凭题目文本核对"的方法完全漏掉的几类 bug。

### Round 10 — 用户手动运行 + 人工核对（Method A）

用户直接运行 notebook 里的 `fetch_question_definitions()` 拿到 8 份问卷的真实题目定义，
逐一贴出核对，发现并修复：
- **CSAT**：`Resolved Today` `Q13`→`Q5`，`Fix Support` `Q14_TEXT`→`Q6`，`Feedback` `Q3_TEXT`→`Q7`，
  `Comments for Marketing` `Q9`→`Q8`
- **MentalHealth**：`Achieve Goals` `Q13`→`Q6`，`Effective Tools` `Q18`→`Q8`，
  `Feedback Improvements` `Q21_TEXT`→`Q5`
- **Wellbeing**：`Achieve Goals` `Q13`→`Q6`，`Effective Tools` `Q15`→`Q7`，
  `Feedback Improvements` `Q6_TEXT`→`Q9`（`How Quickly Contacted`=`Q4` 确认正确，未改）
- **WellbeingV2**：`Feedback Improvements` `Q6_TEXT`→`Q5`（`Program Type`/NPS/Satisfaction 三个字段
  重新核实后确认正确，未改）
- **MentalHealth `Q22`→`Q2`**（`ProviderNo`/`Provider/Program/Staff` 来源）：交叉核对 Qlik md 第795行
  注释"QID22 – Which Service"，确认这是纯 QIDnn→Qnn 编号漂移，非设计错误

### Round 11 — 全面回归审查（不预设方向）

用子代理对整个 notebook 做无预设结论的全字段复核（不只是 Q 编号），发现3处新问题：
1. **`Survey Name` 硬编码问题**：6份问卷 + `Qualtrics_Questions` 的 `Survey Name` 之前用写死的
   Python 字典（`SURVEY_NAMES`），而 Qlik 用的是 `ApplyMap('Survey_MAP', Survey_id)`——
   `Survey_MAP` 基于**实时抓取**的 `Qualtrics_Surveys` 表构建，问卷改名会实时反映。已修复：
   改用 `SURVEY_NAME_MAP`（从当次运行抓到的 `Qualtrics_Surveys` DataFrame 构建），忠实还原
   Qlik 的动态查找行为
2. **`qlik_date_only()` 缺少错误容忍**：原实现 `pd.to_datetime(series).dt.normalize()` 没加
   `errors="coerce"`，非法/空白日期会直接抛异常崩溃整个函数，而 Qlik 的 `date#()` 对同样
   情况是逐行静默返回 `Null()`、不中断。已修复加上 `errors="coerce"`
3. **`Location` 字段未列入排除清单**：6份问卷都省略了 `GeoMakePoint(...)`，但顶部 markdown
   排除清单没写明，属于文档完整性问题，已补充说明

### Round 12 — CSAT + HealthServices 真实 CSV + ImportId 深度核实（首次引入这个方法）

对 CSAT 和 HealthServices 实际发起真实 `export-responses` 导出，用 CSV 第2行 ImportId
逐一核实，发现：

- **CSAT — 3处严重"张冠李戴"**（不是缺失，是读到了别的题目的真实数据）：
  - `Customer Satisfaction`：读的 `Q10`（真实导出里根本不存在这个 tag）→ 改为 `Q2`
  - `Customer Effort`：读的 `Q8`（真实是"营销同意"题的数据）→ 改为 `Q3`
  - `Net Promoter Score`：读的 `Q2`（真实是 Satisfaction 题的数据）→ 改为 `Q4`
  - CSAT 真实存在的题目 tag 范围确认是 `Q1`~`Q8`（`Q1` 是介绍文字块不使用），`Q2`~`Q8`
    共7个 tag 现已全部核实完毕（其余4个之前就是对的：`Q5`=Resolved Today，`Q6`=Fix Support，
    `Q7`=Feedback，`Q8`=Comments for Marketing）
- **HealthServices — `Q3` 多选题拆分**：`How did you hear`之前读单一的 `Q3` 列（真实不存在，
  这是一道多选题）。真实导出拆分成 `Q3_1`~`Q3_6`（每个选项一列）+ `Q3_6_TEXT`（"Other"自由
  文本）。已新增共享 helper `multiselect_join()`，把非空选项逗号拼接还原成单一字段；用
  该问卷全部18行真实数据验证过单选/双选/全空三种情况都能正确处理。还原格式（逗号拼接）是
  合理推断，未能与 Qlik 历史 QVD 产出逐字节核对（无该数据可比对），但字段来源本身
  （`Q3_1`~`Q3_6`均confirmed对应`QID3`）确认无误，不存在张冠李戴风险

### Round 13 — 剩余5份问卷全字段核实 + 复核验证

对 POC、HealthServices（补验部分字段）、MentalHealth、Wellbeing、WellbeingV2 做和 CSAT
同等深度的核实（真实 CSV + ImportId），发现并修复4处同一模式的 bug：

- **POC** `How did you hear about Other`：`Q5_TEXT`→`Q5`
- **POC** `Feedback`：`Q7_TEXT`→`Q7`
- **HealthServices** `Feedback`：`Q9_TEXT`→`Q9`
- **HealthServices** `Feedback Improvements`：`Q18_TEXT`→`Q18`

根因：这几道题都是纯 TE（自由文本）类型题，真实 CSV 列名本身没有 `_TEXT` 后缀——`_TEXT`
只出现在 CSV 第2行 ImportId 元数据里（如 `{"ImportId":"QID5_TEXT"}`），是 Qualtrics 内部
追踪标识，不是真实列名。代码之前把 ImportId 里的后缀误当作了列名，导致这4个字段此前
一直静默产出全空值（不报错，纯粹数据丢失）。

修复后又发起一轮独立复核确认：4处修复全部生效，且 5 份问卷全部43个 Qnn 字段引用逐一
核实无新问题（MentalHealth/Wellbeing/WellbeingV2 全部字段本来就正确；HealthServices 的
`Q3` 多选拆分/NPS/`Q12`/`Q24` 确认正确）。

**至此，全部6份问卷（CSAT + 这5份）的 Qnn 字段核实工作已完整覆盖，方案1（全表全列扫描）
收尾，没有已知未解决的漂移/张冠李戴问题。**

### 仍然存在的、诚实的不确定性（不属于"已解决"，需要明确说明的边界）

即使 Qnn 字段核实已经完整覆盖，也不代表 notebook 已经在所有维度上做到滴水不漏。以下4点
是尚未验证或有意排除的部分，应对未来任何人（含未来的自己）诚实说明，避免误以为"全面复刻"
没有任何限定：

1. **非 Qnn 字段没有做同等深度验证**——`Age`/`Gender`/`Postcode`/`Product` 这类原始透传
   字段，因为不涉及 `QIDnn`↔`Qnn` 漂移风险，没有被纳入这轮核实。理论上风险很低（直接从
   CSV 透传，不涉及题目编号翻译），但严格说没有被"证明"过，只是"没有理由怀疑"。
2. **`Q3` 多选题的还原格式未与历史产出核对**——逗号拼接是合理选择，字段来源本身
   （`Q3_1`~`Q3_6` 确实都对应 `QID3`）已确认无误，但具体拼接成什么样的字符串格式，没有
   和 Qlik 历史 `.qvd` 产出比对过，格式风格上不能保证100%一致（无该历史数据可比对）。
3. **notebook 从未被完整跑通一次并把输出正式存档审查**——用户多次手动运行、抽查过关键
   字段，抽查均通过，但没有做过"从头到尾跑一次、把全部6份问卷的完整输出存下来做系统性
   最终验收"这一步。
4. **范围排除是有意为之，不是遗漏，但如果理解为"全面"需要澄清**——Provider Type/Address/
   Suburb/State/Postcode 等 Paragon BRONZE 依赖字段、`DataforBI`/`DataforScreen`/
   `DataforHCS_NPS_Calcs` 这些下游产物，都被 notebook 开头 markdown 明确排除，不影响
   "复刻范围内的真实性"，但不在这次"全面复刻"的验证范围内。

### 新建：`qualtrics_survey_change_check.ipynb`（漂移检测机制）

鉴于 QIDnn↔Qnn 编号漂移会随问卷被编辑而持续复发（不是一次性问题），新建了一份独立、
轻量的检测 notebook：读取 Qualtrics `/surveys` API 的 `lastModified` 时间戳，和一份
`survey_baseline.json`（记录上次核实完成时的状态）做比对，如果某份问卷被编辑过就打印
警告，提示需要重新核实字段映射。**只做检测/提醒，不做自动修复，也不能定位具体哪个字段
变了**——真正定位问题仍需重跑本次用的"真实CSV+ImportId"核实方法。已首次运行并建立
baseline（2026-07-03，对应本轮全部核实完成后的状态）。

## 待办

- [x] ~~若要落库 SQL Server，需决定用 pandas + pyodbc 直接写入，还是重新捡起 ADF/Data Flow 路径~~
      —— 已决定用 pandas + pyodbc，`qualtrics_fetch.py` 已落地，6 份问卷抓取+转换已用真实数据验证通过
- [x] ~~notebook 定时调度方案尚未落地~~ —— 已确定 VM + Windows Task Scheduler，VM 端写入 SQL Server
      已验证成功（`write_test.py`）
- [ ] **（阻塞）** 向 Trev 确认：`copy.ps1` 被删除后，ADO Artifact 到 VM 的同步机制现在是什么
- [ ] **（阻塞）** 向 Trev 确认 VM 系统时区（悉尼时间 or UTC），影响时间戳字段解读
- [ ] 在 VM 上实际运行 `qualtrics_fetch.py`，验证 6 张表写入 `BRONZE.qua.*` 成功（本机受限于 ODBC
      驱动版本不匹配，未能验证到写入这一步）
- [ ] 编写 `NPS_Score` 的 SQL Server 端 Stored Procedure（读取 6 张 `qua` 表做 `UNION ALL` + 按
      `Member Number` 过滤空值），替代原计划中 Python 侧的 concat 逻辑
- [ ] （可选，超出当前目标范围）`DataforBI`/`DataforHCS_NPS_Calcs` 的复刻，需先补 Feedback 类字段
- [ ] （长期）API Token 改用环境变量/Key Vault，避免明文——本仓库与 `DataEngineering` 仓库均维持
      「先跑通再处理」的决定
- [ ] （长期）`qualtrics_survey_change_check.ipynb` 目前只能靠人工记得去跑，没有自动化触发机制；如果之后有定时调度基础设施，可以考虑让这个检测作为每次主 notebook 运行前的前置步骤
