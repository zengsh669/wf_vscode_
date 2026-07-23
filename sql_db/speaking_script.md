
## Opening (before Slide 1) — ~15 sec

10 to 15 mins or so; take you through the data analytics, westfund data platform structure, bi reporting; hand over to gus to cover off data governence area

---

## SLIDE 1 — Title: Data Engineering — ~30 sec

My role is divided into three areas. Fifty percent is Data Engineering. It's the pipelines and the data warehouse behind every report.

Twenty percent is BI Development — building the actual Power BI reports, and moving us away from Qlik.

Thirty percent lererage tools such Python to automate procedures, and make our workflows smarter, to fix gaps in our day-to-day process.

Let's start with Data Engineering.

---

## SLIDE 2 — Ingestion Paths — ~1.5–2 min

So there are two types of data we deal with right now. Let me explain this simply first.

Some of our data is very organized — like a spreadsheet, or a table in a database, with clear rows and columns, and every record has the same fields. We call this "structured" data. This is what comes from our normal business systems — Paragon, ConnX, Touchpoint, Sage

Other data is more flexible — like JSON, XML, or even email. This is the kind of data we get from digital platforms and surveys, like Qualtrics. We call this "semi-structured" data. But our SQL Server can only store structured data — so semi-structured data needs an extra step before it can go in.

Because these two types are different, they take two different paths into our system. Let me show you each one.

For structured data — it connects directly through a tool called ADF Pipeline. First, it lands in a holding area called ODS — that's short for Operational Data Store. From there, ADF picks out only the tables we need, and moves them into our Data Warehouse.

For Qualtrics — that extra step is a Python script. It pulls the data and cleans it up. Then it goes through an automated process, which builds and releases it on a schedule. It also ends up in the same Data Warehouse.

So — two different types of data, two different paths — but they both end up in the same place. One data warehouse. One source of truth.

---

## SLIDE 3 — Architecture & Systems — ~2–2.5 min

Now let's look at the architecture itself, and which systems are already connected.

We use a three-layer model. Bronze is where raw data lands — nothing is changed yet. Silver is where we clean the data and apply business rules. Gold is what Power BI connects to directly — this is the layer that's ready for reporting.

[Point to the boxes] This setup keeps everything consistent. Every department works from the same numbers, because it all comes from the same three-layer process.

Now — which systems are actually connected. In Bronze, fully connected, we have Paragon, Touchpoint, WE2DAT, and WestfundRPA. In ODS — meaning they've landed there, but haven't been pulled into Bronze yet — we have ConnX and Vouchers. And still in progress, we have D4W and Qualtrics.

---

## SLIDE 4 — Reliability Roadmap — ~1.5–2 min

This slide is about how we keep the data trustworthy — not just moving it, but making sure it's correct.

First, already live — we have daily automated health checks. Every day, the system checks if the data volumes look normal, and if anything in the table structure has changed. If something looks wrong, we catch it early — before it shows up in a report.

Second, in progress — data quality checks, or DQ. The business rules for what counts as "good data" are still being defined. But on my side, the technical part is already built and ready to go.

Third, next up — a standard framework for dimension and fact tables. This is the technical foundation for how we structure our data models — naming rules, primary key strategy, constraints, audit fields, and support for tracking history over time. The design is finished. We just need the business definitions confirmed before we start building.

That's Data Engineering. Now let's move to BI Development.

---

## SLIDE 5 — Title: BI Development — ~20–30 sec

This is twenty percent of my role — building Power BI reports, and migrating us away from Qlik.

---

## SLIDE 6 — Power BI vs Qlik: Why We're Migrating — ~1–1.5 min

Quick context — Power BI is Microsoft's business intelligence tool. It's replacing Qlik as our main reporting platform. Here's why.

First, data residency and control. We run Power BI Report Server on our own servers — on-premises. All our data stays inside our network.

Second, Microsoft integration. Power BI works natively with Teams, Outlook, Excel, and SharePoint. No separate login, no separate system.

Third, ecosystem. Power BI has a large marketplace of visuals, and it supports Python and R scripting. There's a big global community behind it too.

And fourth — momentum. Power BI is the market leader, and Microsoft keeps investing in it — things like Power BI MCP and Fabric Skills, which connect AI tools directly into how we build reports.

---

## SLIDE 7 — Delivery Status — ~1–1.5 min

On the left — new Power BI reports. Five are already done: Monthly Membership Report, Gross Margin Report, Claims Dashboard for HCS, Portfolio Dashboard, and Monthly Digital Reporting Automation. Two more are in progress — the Dental Centre Financial Dashboard, and Telephone System Reporting.

On the right — our Qlik migration progress. Eleven apps are migrated or being migrated to Power BI right now — for example, Compensation Claims, Retained Members, and Rebates. And twenty-eight legacy apps have already been archived — things like the old Profitability App and Membership Reporting tool.

That's BI Development. Last part — Data Tooling and Automation.

---

## SLIDE 8 — Title: Data Tooling & Automation — ~20–30 sec

This is thirty percent of my time. These are tools I build outside the main pipeline — to fix gaps, save time, and make our work more automated.

---

## SLIDE 9 — Python Tools Built Along the Way — ~3–4 min
*(Use your own examples/impact stories here to fill the time)*

Four tools I want to highlight.

**QVD Converter** — QVD is Qlik's own file format. This tool converts QVD files into CSV, Parquet, or JSON — normal formats anyone can use. And you don't even need a Qlik license to run it.
*[Add a short example: when did this save time / what problem did it solve]*

**Snapshot Backup** — this pulls together our daily data snapshots into one clean Parquet format. It means we can go back and check what the data looked like on any specific day in the past.
*[Add a short example]*

**ABS GEO Mapping** — this does location-based analysis, down to street level. It uses Australia's national address database, plus geographic boundary data from the ABS.
*[Add a short example]*

**DWH Lineage Map** — this one automatically draws a diagram showing how data flows through our whole Bronze-Silver-Gold system. It shows exactly where each piece of data comes from, and where it goes.
*[Add a short example]*

---

## Closing (no dedicated slide) — ~20–30 sec

So to sum up — fifty percent of my work is the engineering underneath everything, twenty percent is the reports you actually see, and thirty percent is the tools that make our day-to-day work faster and smarter. Happy to take any questions.

---

### Notes for practice
- Total word count is written for roughly 12–13 minutes at a calm, clear pace.
- Slide 9 has open space — fill it with real numbers or short stories (e.g. "this used to take 3 hours, now it takes 10 minutes") to naturally stretch it to fill your time budget.
- Practice out loud once with a timer before the real thing — non-native pacing is often a bit slower, so this script leaves you buffer room under the 15-minute limit.
