/*
 Clinical Hours Worked — denominator for Optometrist Utilisation (draft, not business-approved)
 Grain: one row per branch per day — "how many hours SHOULD have been worked here today",
 before subtracting leave (leave subtraction is a separate, not-yet-built second layer).

 Source of the master list below: select_ConnX_Optometrist_Leave.sql (ConnX HR/payroll system,
 separate database from Optomate — matched by optometrist name, no shared key). Hand-maintained,
 not parsed from ConnX's free-text Work Pattern Description — see DESIGN.md.

 Excludes 2 of the 12 ConnX-confirmed optometrists whose employment ended before Optomate's data
 even starts (2026-02-23, the earliest APPOINTMENT date found across all branches — see DESIGN.md):
   - Clothier, Gary   (Lithgow) — Position Held To 2022-09-01
   - Nguyen, Trieu    (Lithgow) — Position Held To 2025-07-01
 Both predate the data window entirely, so no attendance data could ever exist for them — this
 also sidesteps needing to parse Trieu Nguyen's ambiguous "TC35hrs Casual" Work Pattern.

 Everyone below works exactly 7 hours/day (verified from every parsed Work Pattern Description in
 the ConnX roster) on their rostered days — only the SET of rostered weekdays differs per person.
*/

DECLARE @OptometristRoster TABLE (
    FullName        VARCHAR(100),
    BranchIdentifier VARCHAR(10),   -- mapped from ConnX Cost Centre to Optomate's BRANCH_IDENTIFIER
    PositionFrom    DATE,
    PositionTo      DATE,           -- NULL = still current
    HoursPerDay     INT,
    DaysOff         VARCHAR(60)     -- comma-separated weekday names this person does NOT work
);
INSERT INTO @OptometristRoster VALUES
    ('Anastovski, Steve', 'WOL', '2026-06-09', NULL,         7, 'Saturday,Sunday'),
    ('Anwari, Zahra',      'ORA', '2023-02-06', NULL,         7, 'Saturday,Sunday'),
    ('Bemrose, Colin',     'DUB', '2025-05-01', NULL,         7, 'Saturday,Sunday'),
    ('Bemrose, Trevor',    'DUB', '2014-07-01', NULL,         7, 'Saturday,Sunday'),
    ('Burmi, Mukesh',      'LIT', '2023-09-04', NULL,         7, 'Saturday,Sunday'),
    ('Khou, Vincent',      'LIT', '2023-06-19', NULL,         7, 'Saturday,Sunday'),
    ('Lam, Anthony',       'MAK', '2024-07-08', NULL,         7, 'Saturday,Sunday'),
    ('Liao, Pei-Chun',     'ORA', '2024-07-08', NULL,         7, 'Saturday,Sunday'),
    ('McLeish, June',      'ORA', '2014-07-01', NULL,         7, 'Monday,Thursday,Friday,Saturday,Sunday'),
    ('Nguyen, Ronald',     'MAK', '2015-03-30', '2024-09-12', 7, 'Saturday,Sunday'),  -- position: Optometrist
    ('Nguyen, Ronald',     'MAK', '2024-09-13', NULL,         7, 'Saturday,Sunday');  -- position: Optometrist Lead
                                                                                      -- (kept as two rows, one per
                                                                                      -- ConnX position segment, even
                                                                                      -- though hours/days happen to
                                                                                      -- match today — a future
                                                                                      -- schedule change on either
                                                                                      -- segment would otherwise be
                                                                                      -- silently lost by merging)

-- ============================================================================
-- Excluded from the roster above (employment ended before Optomate data starts,
-- 2026-02-23 — see DESIGN.md "Branches confirmed active" note):
--   Clothier, Gary  — Lithgow — Position Held To 2022-09-01
--   Nguyen, Trieu   — Lithgow — Position Held To 2025-07-01
-- ============================================================================

-- ============================================================================
-- LAYER 1 — theoretical hours available per branch per day, NOT yet reduced by
-- leave. Days considered are ONLY days with at least one attended appointment
-- at that branch (same "Working Days" definition as select_Chair_Utilisation.sql
-- — a day with zero appointments, e.g. a public holiday, is excluded because it
-- simply never appears in APPOINTMENT, not via an explicit filter). A calendar-
-- generated date spine was considered and rejected (2026-09-11) — it would have
-- counted days with no attendance at all, which is wrong by definition.
-- ============================================================================
IF OBJECT_ID('tempdb..#BranchWorkingDays') IS NOT NULL DROP TABLE #BranchWorkingDays;

SELECT DISTINCT
    a.BRANCH_IDENTIFIER        AS BranchIdentifier,
    CAST(a.STARTDATE AS DATE)  AS TheDate
INTO #BranchWorkingDays
FROM APPOINTMENT a
WHERE a.APP_PROGRESS IN (2, 3, 4, 5, 10)  -- Attended (same definition as the other two metrics)
  AND a.IS_BREAK = 0
  AND a.PATIENTID > 0;

IF OBJECT_ID('tempdb..#Layer1_TheoreticalHours') IS NOT NULL DROP TABLE #Layer1_TheoreticalHours;

SELECT
    r.BranchIdentifier,
    d.TheDate,
    DATENAME(WEEKDAY, d.TheDate)                           AS WeekdayName,
    COUNT(*)                                                AS OptometristsRostered,
    COUNT(*) * MAX(r.HoursPerDay)                           AS Theoretical_Available_Hours
    -- MAX(HoursPerDay) here is safe only because everyone is 7 hrs/day today;
    -- if that ever varies per person, this needs SUM(HoursPerDay) per person-day instead.
INTO #Layer1_TheoreticalHours
FROM #BranchWorkingDays d
JOIN @OptometristRoster r
    ON r.BranchIdentifier = d.BranchIdentifier
   AND d.TheDate >= r.PositionFrom
   AND d.TheDate <= ISNULL(r.PositionTo, '9999-12-31')
   AND CHARINDEX(DATENAME(WEEKDAY, d.TheDate), r.DaysOff) = 0   -- not a day off for this person
GROUP BY r.BranchIdentifier, d.TheDate;

-- Output Layer 1 on its own for inspection.
SELECT * FROM #Layer1_TheoreticalHours ORDER BY BranchIdentifier, TheDate;

DROP TABLE #BranchWorkingDays;

-- ============================================================================
-- LAYER 2 — subtract leave. Source: the leave-history half of
-- select_ConnX_Optometrist_Leave.sql (ConnX.dbo.q2vEmployeeLeaveHistory), with
-- Cost Centre mapped to Optomate's BRANCH_IDENTIFIER the same way as the roster
-- above.
--
-- A leave record's `hours` is the total for the WHOLE date_start–date_end span
-- (verified 2026-09-11: one record showed 105 hours across a 15-working-day
-- span, i.e. 7 hrs/day — NOT 105 hours in a single day). Rather than working
-- out how many rostered days fall in that span and dividing, this uses a
-- simpler equivalent: cap the leave applied on any one day at 7 hours (one
-- person can only ever work/be absent for at most a single day's worth of
-- hours on any given day) — same result as dividing 105 by a 15-day span
-- (105/15 = 7) without needing to compute the span's working-day count.
--
-- Multiple leave records can hit the same person-day (verified 2026-09-11 —
-- common, not rare). Decision (2026-09-11): sum all matching records for that
-- person-day FIRST, then cap the sum at 7 — capping each record individually
-- before summing would let two overlapping large-span records each contribute
-- up to 7 hours and double-count a single day.
-- ============================================================================
IF OBJECT_ID('tempdb..#LeaveByPersonDay') IS NOT NULL DROP TABLE #LeaveByPersonDay;

;WITH LeaveMapped AS (
    SELECT
        e.surname + ', ' + e.given_name    AS FullName,
        CASE pos.Department
            WHEN 'Wollongong Eye Care' THEN 'WOL'
            WHEN 'Orange Eye Care'     THEN 'ORA'
            WHEN 'Dubbo Eye Care'      THEN 'DUB'
            WHEN 'Lithgow Eye Care'    THEN 'LIT'
            WHEN 'Mackay Eye Care'     THEN 'MAK'
            ELSE NULL
        END                                 AS BranchIdentifier,
        h.date_start,
        h.date_end,
        h.hours
    FROM [ConnX].[dbo].[q2employees] e
    JOIN [ConnX].[dbo].[q2vHREmployee_Position] pos
        ON e.emp_code = pos.emp_code
    JOIN [ConnX].[dbo].[q2vEmployeeLeaveHistory] h
        ON e.emp_code = h.emp_code
    WHERE pos.Role_Name LIKE '%Optometrist%'
),
-- Every calendar day each leave record spans, joined against the roster to
-- confirm that person actually works that branch/day (skip their days off).
LeaveDays AS (
    SELECT
        lm.BranchIdentifier,
        d.TheDate,
        lm.FullName,
        lm.hours AS RecordTotalHours
    FROM LeaveMapped lm
    JOIN #Layer1_TheoreticalHours d
        ON d.BranchIdentifier = lm.BranchIdentifier
       AND d.TheDate >= CAST(lm.date_start AS DATE)
       AND d.TheDate <= CAST(lm.date_end AS DATE)
)
SELECT
    BranchIdentifier,
    TheDate,
    FullName,
    SUM(RecordTotalHours)                          AS RawLeaveHoursSummed,
    CASE WHEN SUM(RecordTotalHours) > 7 THEN 7 ELSE SUM(RecordTotalHours) END
                                                    AS LeaveHoursCapped
INTO #LeaveByPersonDay
FROM LeaveDays
GROUP BY BranchIdentifier, TheDate, FullName;

-- ============================================================================
-- LAYER 2 RESULT — Layer 1 minus capped leave, summed per branch/day.
-- ============================================================================
SELECT
    l1.BranchIdentifier,
    l1.TheDate,
    l1.Theoretical_Available_Hours,
    ISNULL(SUM(lv.LeaveHoursCapped), 0)                                AS Total_Leave_Hours,
    l1.Theoretical_Available_Hours - ISNULL(SUM(lv.LeaveHoursCapped), 0)
                                                                        AS Clinical_Hours_Worked
FROM #Layer1_TheoreticalHours l1
LEFT JOIN #LeaveByPersonDay lv
    ON lv.BranchIdentifier = l1.BranchIdentifier
   AND lv.TheDate = l1.TheDate
GROUP BY l1.BranchIdentifier, l1.TheDate, l1.Theoretical_Available_Hours
ORDER BY l1.BranchIdentifier, l1.TheDate;

DROP TABLE #Layer1_TheoreticalHours;
DROP TABLE #LeaveByPersonDay;
