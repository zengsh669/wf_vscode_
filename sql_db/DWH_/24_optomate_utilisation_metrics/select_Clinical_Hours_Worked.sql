/*
 Clinical Hours Worked — denominator for Optometrist Utilisation (draft, not business-approved)
 Grain: one row per branch per day.

 Design (business-confirmed, 2026-09-15): each branch has a FIXED clinical
 capacity per day — 7 hours for a single-optometrist branch, 14 hours for ORA
 (two optometrist positions). This capacity does NOT depend on who is rostered
 or who shows up — if the rostered optometrist takes leave, a locum covers the
 gap, so the branch's total available hours stay constant. Locums are highly
 mobile (not tied to one branch) and are deliberately NOT tracked individually
 — only the rostered optometrists' leave matters for this calculation.

 Two layers:
   LAYER 1 — fixed branch capacity x working days (days with an attended
   appointment). Replaces the old roster-headcount calculation.
   LAYER 2 — subtract the ROSTERED optometrist's leave (from ConnX), but only
   for days that optometrist was actually scheduled to work (per their
   DaysOff pattern) — a non-rostered day (e.g. JMC's Mon/Thu/Fri) was never
   "her" capacity to begin with, so it can't be leave.

 LAYER 3 (USER_APP_ADJUST / INACTIVE=1 no-show tracking) has been REMOVED
 (2026-09-15) — no longer needed under this design, since locum coverage is
 assumed and not tracked per-person.
*/

-- ============================================================================
-- Branch fixed capacity (hours/day) — business-confirmed, 2026-09-15.
-- ============================================================================
DECLARE @BranchCapacity TABLE (
    BranchIdentifier VARCHAR(10),
    CapacityHours    INT
);
INSERT INTO @BranchCapacity VALUES
    ('DUB', 7),
    ('ORA', 14),
    ('MAK', 7),
    ('LIT', 7),
    ('WOL', 7);

-- ============================================================================
-- Rostered optometrists only (no locums — see header). Source: ConnX,
-- Role_Name IN ('Optometrist','Optometrist Lead'), hand-maintained — see
-- select_ConnX_Optometrist_Leave.sql / DESIGN.md. Used ONLY to determine,
-- per person/day, whether that day was a rostered working day (for Layer 2's
-- leave matching) — NOT to compute branch capacity (that's @BranchCapacity).
-- Identifier = Optomate USER_IDENTIFIER, confirmed against USERS (2026-09-15).
-- ============================================================================
DECLARE @OptometristRoster TABLE (
    FullName        VARCHAR(100),
    Identifier      VARCHAR(10),
    BranchIdentifier VARCHAR(10),
    PositionFrom    DATE,
    PositionTo      DATE,           -- NULL = still current
    HoursPerDay     INT,
    DaysOff         VARCHAR(60)     -- comma-separated weekday names this person does NOT work
);
INSERT INTO @OptometristRoster VALUES
    ('Anastovski, Steve', 'SA',  'WOL', '2026-06-09', NULL,         7, 'Saturday,Sunday'),
    ('Anwari, Zahra',      'ZA', 'ORA', '2023-02-06', NULL,         7, 'Saturday,Sunday'),
    ('Bemrose, Trevor',    'TB', 'DUB', '2014-07-01', NULL,         7, 'Saturday,Sunday'),
    ('Burmi, Mukesh',      'MB', 'LIT', '2023-09-04', NULL,         7, 'Saturday,Sunday'),
    ('McLeish, June',      'JMC','ORA', '2014-07-01', NULL,         7, 'Monday,Thursday,Friday,Saturday,Sunday'),
    ('Nguyen, Ronald',     'RN', 'MAK', '2015-03-30', '2024-09-12', 7, 'Saturday,Sunday'),  -- position: Optometrist
    ('Nguyen, Ronald',     'RN', 'MAK', '2024-09-13', NULL,         7, 'Saturday,Sunday');  -- position: Optometrist Lead

-- ============================================================================
-- LAYER 1 — fixed branch capacity x working days. Working days = branch/days
-- with at least one attended appointment (same definition as before — a day
-- with zero appointments, e.g. a public holiday, is excluded automatically
-- because it never appears in APPOINTMENT).
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
    d.BranchIdentifier,
    d.TheDate,
    bc.CapacityHours    AS Theoretical_Available_Hours
INTO #Layer1_TheoreticalHours
FROM #BranchWorkingDays d
JOIN @BranchCapacity bc
    ON bc.BranchIdentifier = d.BranchIdentifier;

-- Output Layer 1 on its own for inspection.
SELECT * FROM #Layer1_TheoreticalHours ORDER BY BranchIdentifier, TheDate;

DROP TABLE #BranchWorkingDays;

-- ============================================================================
-- LAYER 2 — subtract the rostered optometrist's leave, capped at 7 hrs/day
-- per person. Leave only counts on a day that person was actually rostered
-- to work (their DaysOff pattern) — a non-rostered day was never part of
-- their own capacity, so leave can't apply there.
-- ============================================================================
IF OBJECT_ID('tempdb..#RosteredWorkingDays') IS NOT NULL DROP TABLE #RosteredWorkingDays;

-- Every (person, working day) combination where that person was actually
-- rostered to work — i.e. within their position dates and not their day off.
SELECT
    r.FullName,
    r.BranchIdentifier,
    d.TheDate,
    r.HoursPerDay
INTO #RosteredWorkingDays
FROM #Layer1_TheoreticalHours d
JOIN @OptometristRoster r
    ON r.BranchIdentifier = d.BranchIdentifier
   AND d.TheDate >= r.PositionFrom
   AND d.TheDate <= ISNULL(r.PositionTo, '9999-12-31')
   AND CHARINDEX(DATENAME(WEEKDAY, d.TheDate), r.DaysOff) = 0   -- not this person's day off
GROUP BY r.FullName, r.BranchIdentifier, d.TheDate, r.HoursPerDay;

-- How much of the branch's fixed capacity actually had a rostered optometrist
-- scheduled at all, per branch/day — e.g. ORA on a Mon/Thu/Fri only has ZA
-- rostered (JMC's day off), so only 7 of the 14 capacity hours were ever
-- "hers" to begin with. The gap between capacity and this is structural
-- (no optometrist rostered), distinct from leave (rostered but absent).
IF OBJECT_ID('tempdb..#ScheduledHoursByBranchDay') IS NOT NULL DROP TABLE #ScheduledHoursByBranchDay;

SELECT
    BranchIdentifier,
    TheDate,
    SUM(HoursPerDay) AS Scheduled_Hours   -- sums each rostered person's own hours/day,
                                           -- not a fixed 7 — correct even if HoursPerDay
                                           -- ever varies per person
INTO #ScheduledHoursByBranchDay
FROM #RosteredWorkingDays
GROUP BY BranchIdentifier, TheDate;

IF OBJECT_ID('tempdb..#LeaveByPersonDay') IS NOT NULL DROP TABLE #LeaveByPersonDay;

;WITH LeaveMapped AS (
    SELECT
        e.surname + ', ' + e.given_name    AS FullName,
        h.date_start,
        h.date_end,
        h.hours
    FROM [ConnX].[dbo].[q2employees] e
    JOIN [ConnX].[dbo].[q2vHREmployee_Position] pos
        ON e.emp_code = pos.emp_code
    JOIN [ConnX].[dbo].[q2vEmployeeLeaveHistory] h
        ON e.emp_code = h.emp_code
       AND h.date_start >= pos.Date_Held_From                      -- leave must fall within THIS
       AND h.date_start <= ISNULL(pos.Date_Held_To, '9999-12-31')  -- position segment, not any
                                                                     -- segment this emp_code ever
                                                                     -- held (fixes fan-out — see
                                                                     -- select_ConnX_Optometrist_Leave.sql)
    WHERE pos.Role_Name LIKE '%Optometrist%'
),
-- Every calendar day each leave record spans, joined against ONLY the days
-- that person was actually rostered to work (skip their days off).
LeaveDays AS (
    SELECT
        rwd.BranchIdentifier,
        rwd.TheDate,
        rwd.FullName,
        rwd.HoursPerDay,
        lm.hours AS RecordTotalHours
    FROM LeaveMapped lm
    JOIN #RosteredWorkingDays rwd
        ON rwd.FullName = lm.FullName COLLATE DATABASE_DEFAULT
       AND rwd.TheDate >= CAST(lm.date_start AS DATE)
       AND rwd.TheDate <= CAST(lm.date_end AS DATE)
)
SELECT
    BranchIdentifier,
    TheDate,
    FullName,
    CASE WHEN SUM(RecordTotalHours) > MAX(HoursPerDay) THEN MAX(HoursPerDay) ELSE SUM(RecordTotalHours) END
                                                    AS LeaveHoursCapped
    -- capped at this person's own HoursPerDay, not a fixed 7 — correct even
    -- if HoursPerDay ever varies per person (same fix as Scheduled_Hours)
INTO #LeaveByPersonDay
FROM LeaveDays
GROUP BY BranchIdentifier, TheDate, FullName;

DROP TABLE #RosteredWorkingDays;

-- ============================================================================
-- LAYER 2 RESULT — Layer 1 (fixed branch capacity) minus capped leave,
-- summed per branch/day. Clinical_Hours_Worked is unchanged by the split
-- below — Optom_Not_Scheduled_Hours and Total_Leave_Hours are just two
-- different reasons for the same gap (structural vs. leave), shown
-- separately for visibility, not double-subtracted.
-- ============================================================================
SELECT
    l1.BranchIdentifier,
    l1.TheDate,
    DATENAME(WEEKDAY, l1.TheDate)                                      AS WeekdayName,
    l1.Theoretical_Available_Hours,
    l1.Theoretical_Available_Hours - ISNULL(sh.Scheduled_Hours, 0)     AS Optom_Not_Scheduled_Hours,
    ISNULL(SUM(lv.LeaveHoursCapped), 0)                                AS Total_Leave_Hours,
    l1.Theoretical_Available_Hours                                     AS Clinical_Hours_Worked
    -- Clinical_Hours_Worked = fixed branch capacity, full stop — NOT reduced
    -- by leave (2026-09-15 fix, synced from select_Optometrist_Utilisation.sql).
    -- Leave is covered by a locum, so branch capacity doesn't shrink; the
    -- numerator counts locum-covered appointments too, so subtracting leave
    -- from the denominator without adding locum hours back was pushing
    -- Optometrist_Utilisation over 100% (e.g. MAK 211%). Optom_Not_Scheduled_Hours
    -- / Total_Leave_Hours remain as visibility columns only — not subtracted here.
FROM #Layer1_TheoreticalHours l1
LEFT JOIN #ScheduledHoursByBranchDay sh
    ON sh.BranchIdentifier = l1.BranchIdentifier
   AND sh.TheDate = l1.TheDate
LEFT JOIN #LeaveByPersonDay lv
    ON lv.BranchIdentifier = l1.BranchIdentifier
   AND lv.TheDate = l1.TheDate
GROUP BY l1.BranchIdentifier, l1.TheDate, l1.Theoretical_Available_Hours, sh.Scheduled_Hours
ORDER BY l1.BranchIdentifier, l1.TheDate;

DROP TABLE #Layer1_TheoreticalHours;
DROP TABLE #ScheduledHoursByBranchDay;
DROP TABLE #LeaveByPersonDay;
