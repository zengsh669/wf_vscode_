/*
 Optometrist Utilisation — FACT TABLE (draft, not business-approved)
 Grain: one row per attended appointment. Numerator only (actual duration) —
 the denominator (Clinical Hours Worked) is computed separately from ConnX
 (HR/payroll, a different database from Optomate) and joined in at the
 METRICS stage, per branch per day.
 Attended = APP_PROGRESS IN (2,3,4,5,10) (same definition as the other two metrics).
 This metric is BRANCH+DAY grain, not per-optometrist — see DESIGN.md for why
 (the ConnX roster only covers named optometrists with clean HR records; locum
 optometrists are not yet distinguished, so a per-person split isn't reliable
 yet, whereas a branch/day total sidesteps that gap).
 Full rules and evidence: DESIGN.md.
*/

IF OBJECT_ID('tempdb..#OptometristAppointmentDetail') IS NOT NULL DROP TABLE #OptometristAppointmentDetail;

SELECT
    a.ID                AS AppointmentID,
    a.BRANCH_IDENTIFIER AS BranchIdentifier,
    a.USER_IDENTIFIER   AS OptometristIdentifier,
    a.PATIENTID         AS PatientID,
    CAST(a.STARTDATE AS DATE) AS AppointmentDate,
    a.STARTDATE         AS StartDateTime,
    a.ENDDATE           AS EndDateTime,
    a.DURATION          AS DurationMinutes  -- verified reliable, matches DATEDIFF(MINUTE, STARTDATE, ENDDATE)
INTO #OptometristAppointmentDetail
FROM APPOINTMENT a
WHERE a.APP_PROGRESS IN (2, 3, 4, 5, 10)  -- Attended (see DESIGN.md decode table)
  AND a.IS_BREAK = 0
  AND a.PATIENTID > 0;

-- Output the fact table.
SELECT *
FROM #OptometristAppointmentDetail
ORDER BY AppointmentDate DESC, BranchIdentifier, AppointmentID;

-- ============================================================================
-- DENOMINATOR — Clinical Hours Worked, per branch per day. Reuses the fixed-
-- capacity + rostered-leave logic from select_Clinical_Hours_Worked.sql (see
-- that file / DESIGN.md for full rationale).
--
-- Design (business-confirmed, 2026-09-15): each branch has a FIXED clinical
-- capacity per day — 7 hours for a single-optometrist branch, 14 hours for
-- ORA (two optometrist positions) — regardless of who is rostered or shows
-- up, since a locum covers any gap. Locums are highly mobile and are
-- deliberately NOT tracked individually — only the rostered optometrists'
-- leave matters here. The old roster-headcount calculation and the
-- USER_APP_ADJUST / INACTIVE=1 no-show layer have both been REMOVED
-- (2026-09-15) under this design.
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

-- Rostered optometrists only (no locums — see above). Identifier = Optomate
-- USER_IDENTIFIER, confirmed against USERS (2026-09-15). Used ONLY to
-- determine, per person/day, whether that day was a rostered working day
-- (for leave matching) — NOT to compute branch capacity (that's @BranchCapacity).
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

IF OBJECT_ID('tempdb..#BranchWorkingDays') IS NOT NULL DROP TABLE #BranchWorkingDays;

SELECT DISTINCT
    BranchIdentifier,
    AppointmentDate AS TheDate
INTO #BranchWorkingDays
FROM #OptometristAppointmentDetail;

IF OBJECT_ID('tempdb..#Layer1_TheoreticalHours') IS NOT NULL DROP TABLE #Layer1_TheoreticalHours;

SELECT
    d.BranchIdentifier,
    d.TheDate,
    bc.CapacityHours    AS Theoretical_Available_Hours
INTO #Layer1_TheoreticalHours
FROM #BranchWorkingDays d
JOIN @BranchCapacity bc
    ON bc.BranchIdentifier = d.BranchIdentifier;

DROP TABLE #BranchWorkingDays;

-- Every (person, working day) combination where that person was actually
-- rostered to work — i.e. within their position dates and not their day off.
IF OBJECT_ID('tempdb..#RosteredWorkingDays') IS NOT NULL DROP TABLE #RosteredWorkingDays;

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
-- scheduled at all, per branch/day — the gap between capacity and this is
-- structural (no optometrist rostered), distinct from leave (rostered but absent).
IF OBJECT_ID('tempdb..#ScheduledHoursByBranchDay') IS NOT NULL DROP TABLE #ScheduledHoursByBranchDay;

SELECT
    BranchIdentifier,
    TheDate,
    SUM(HoursPerDay) AS Scheduled_Hours
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
INTO #LeaveByPersonDay
FROM LeaveDays
GROUP BY BranchIdentifier, TheDate, FullName;

DROP TABLE #RosteredWorkingDays;

IF OBJECT_ID('tempdb..#ClinicalHoursWorked') IS NOT NULL DROP TABLE #ClinicalHoursWorked;

SELECT
    l1.BranchIdentifier,
    l1.TheDate,
    l1.Theoretical_Available_Hours,
    l1.Theoretical_Available_Hours - ISNULL(sh.Scheduled_Hours, 0)     AS Optom_Not_Scheduled_Hours,
    ISNULL(SUM(lv.LeaveHoursCapped), 0)                                AS Total_Leave_Hours,
    l1.Theoretical_Available_Hours                                     AS Clinical_Hours_Worked
    -- Clinical_Hours_Worked = fixed branch capacity, full stop — NOT reduced
    -- by leave (2026-09-15 fix). Leave is covered by a locum, so branch
    -- capacity doesn't shrink; the numerator counts locum-covered appointments
    -- too, so subtracting leave from the denominator without adding locum
    -- hours back was pushing Optometrist_Utilisation over 100% (e.g. MAK
    -- 211%). Optom_Not_Scheduled_Hours/Total_Leave_Hours remain as visibility
    -- columns only — not subtracted here.
INTO #ClinicalHoursWorked
FROM #Layer1_TheoreticalHours l1
LEFT JOIN #ScheduledHoursByBranchDay sh
    ON sh.BranchIdentifier = l1.BranchIdentifier
   AND sh.TheDate = l1.TheDate
LEFT JOIN #LeaveByPersonDay lv
    ON lv.BranchIdentifier = l1.BranchIdentifier
   AND lv.TheDate = l1.TheDate
GROUP BY l1.BranchIdentifier, l1.TheDate, l1.Theoretical_Available_Hours, sh.Scheduled_Hours;

DROP TABLE #Layer1_TheoreticalHours;
DROP TABLE #ScheduledHoursByBranchDay;
DROP TABLE #LeaveByPersonDay;

-- ============================================================================
-- METRICS — Optometrist Utilisation = Total Attended Appointment Duration
-- (hours) ÷ Clinical Hours Worked, per branch per day, then rolled up to a
-- per-branch total across the whole date range in the fact table. Grain is
-- BRANCH+DAY, not per-optometrist (see header comment).
-- ============================================================================

-- Roll up the fact table (many appointment rows per branch/day) to exactly
-- one row per branch/day FIRST, before joining to the denominator — the
-- denominator is already one row per branch/day, so joining it directly onto
-- the un-rolled-up fact table and then SUM()-ing would repeat each day's
-- Clinical_Hours_Worked once per appointment that day (verified 2026-09-11:
-- this inflated DUB's denominator to 9,590 hours instead of a few hundred).
IF OBJECT_ID('tempdb..#AttendedByBranchDay') IS NOT NULL DROP TABLE #AttendedByBranchDay;

SELECT
    BranchIdentifier,
    AppointmentDate,
    SUM(DurationMinutes) / 60.0 AS Total_Attended_Duration_Hours
INTO #AttendedByBranchDay
FROM #OptometristAppointmentDetail
GROUP BY BranchIdentifier, AppointmentDate;

-- 1) Per branch per day — split Total_Attended_Duration_Hours between the
-- rostered optometrist and the locum. Business logic (2026-09-15): optom
-- gets first claim on the hours worked, up to its own denominator; anything
-- beyond that spills over to locum, up to locum's denominator. Neither side
-- is capped in the output below — if attended hours exceed a side's
-- denominator, that side's allocated hours are still shown in full (the %
-- in output 3 will then exceed 100%, deliberately, to surface the overload
-- rather than hide it by clamping).
IF OBJECT_ID('tempdb..#SplitByBranchDay') IS NOT NULL DROP TABLE #SplitByBranchDay;

SELECT
    abd.BranchIdentifier,
    abd.AppointmentDate,
    abd.Total_Attended_Duration_Hours,
    chw.Clinical_Hours_Worked,
    chw.Optom_Not_Scheduled_Hours,
    chw.Total_Leave_Hours,
    chw.Clinical_Hours_Worked - (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours)
                                                                        AS Optom_Denominator_Hours,
    chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours              AS Locum_Denominator_Hours,
    -- Optom gets everything attended when there's no locum denominator to
    -- begin with (2026-09-15 fix) — a small overrun on a day with zero
    -- locum coverage is optom working overtime, not a locum showing up;
    -- forcing that overrun onto Locum_Attended_Hours made no business sense
    -- when Locum_Denominator_Hours = 0. Otherwise, optom gets whichever is
    -- smaller: what was attended, or optom's own denominator.
    CASE WHEN (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours) = 0
              THEN abd.Total_Attended_Duration_Hours
         WHEN abd.Total_Attended_Duration_Hours
              <= (chw.Clinical_Hours_Worked - (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours))
         THEN abd.Total_Attended_Duration_Hours
         ELSE (chw.Clinical_Hours_Worked - (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours))
    END                                                                 AS Optom_Attended_Hours,
    -- Locum only gets a share when there's an actual locum denominator to
    -- begin with — whatever's left over once optom's denominator is filled.
    CASE WHEN (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours) = 0
              THEN 0
         WHEN abd.Total_Attended_Duration_Hours
              <= (chw.Clinical_Hours_Worked - (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours))
         THEN 0
         ELSE abd.Total_Attended_Duration_Hours
              - (chw.Clinical_Hours_Worked - (chw.Optom_Not_Scheduled_Hours + chw.Total_Leave_Hours))
    END                                                                 AS Locum_Attended_Hours
INTO #SplitByBranchDay
FROM #AttendedByBranchDay abd
JOIN #ClinicalHoursWorked chw
    ON chw.BranchIdentifier = abd.BranchIdentifier
   AND chw.TheDate = abd.AppointmentDate;

SELECT * FROM #SplitByBranchDay ORDER BY BranchIdentifier, AppointmentDate;

-- 2) Rolled up per branch (whole date range) — utilisation % split out here,
-- not in output 1. Optometrist_Utilisation still uses the unsplit totals
-- (Total_Attended_Duration_Hours / Clinical_Hours_Worked) as the overall
-- figure; Optom_Utilisation_Pct / Locum_Utilisation_Pct use the split hours
-- against each side's own denominator — either can exceed 100% on purpose.
SELECT
    BranchIdentifier,
    SUM(Total_Attended_Duration_Hours)                                 AS Total_Attended_Duration_Hours,
    SUM(Clinical_Hours_Worked)                                         AS Total_Clinical_Hours_Worked,
    SUM(Total_Attended_Duration_Hours) / NULLIF(SUM(Clinical_Hours_Worked), 0)
                                                                        AS Optometrist_Utilisation,
    SUM(Optom_Denominator_Hours)                                       AS Total_Optom_Denominator_Hours,
    SUM(Optom_Attended_Hours)                                          AS Total_Optom_Attended_Hours,
    SUM(Optom_Attended_Hours) / NULLIF(SUM(Optom_Denominator_Hours), 0)
                                                                        AS Optom_Utilisation_Pct,
    SUM(Locum_Denominator_Hours)                                       AS Total_Locum_Denominator_Hours,
    SUM(Locum_Attended_Hours)                                          AS Total_Locum_Attended_Hours,
    SUM(Locum_Attended_Hours) / NULLIF(SUM(Locum_Denominator_Hours), 0)
                                                                        AS Locum_Utilisation_Pct
FROM #SplitByBranchDay
GROUP BY BranchIdentifier
ORDER BY BranchIdentifier;

DROP TABLE #OptometristAppointmentDetail;
DROP TABLE #ClinicalHoursWorked;
DROP TABLE #AttendedByBranchDay;
DROP TABLE #SplitByBranchDay;
