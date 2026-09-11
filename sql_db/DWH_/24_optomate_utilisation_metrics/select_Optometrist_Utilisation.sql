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
-- DENOMINATOR — Clinical Hours Worked, per branch per day. Reuses the full
-- roster + working-day + leave logic from select_Clinical_Hours_Worked.sql
-- (see that file / DESIGN.md for the detailed rationale of every step below —
-- Master roster hand-maintained from ConnX; working days = branch/days with an
-- actual attended appointment, not a calendar spine; leave hours summed per
-- person/day THEN capped at 7, since a leave record's `hours` can span many
-- days, not just date_start).
-- ============================================================================
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
                                                                                      -- ConnX position segment —
                                                                                      -- see select_Clinical_Hours_
                                                                                      -- Worked.sql for why this
                                                                                      -- isn't merged into one row)

-- Excluded from the roster above (employment ended before Optomate data starts,
-- 2026-02-23): Clothier, Gary (Lithgow, to 2022-09-01); Nguyen, Trieu (Lithgow,
-- to 2025-07-01) — see select_Clinical_Hours_Worked.sql / DESIGN.md.

IF OBJECT_ID('tempdb..#BranchWorkingDays') IS NOT NULL DROP TABLE #BranchWorkingDays;

SELECT DISTINCT
    BranchIdentifier,
    AppointmentDate AS TheDate
INTO #BranchWorkingDays
FROM #OptometristAppointmentDetail;

IF OBJECT_ID('tempdb..#Layer1_TheoreticalHours') IS NOT NULL DROP TABLE #Layer1_TheoreticalHours;

SELECT
    r.BranchIdentifier,
    d.TheDate,
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
    CASE WHEN SUM(RecordTotalHours) > 7 THEN 7 ELSE SUM(RecordTotalHours) END AS LeaveHoursCapped
INTO #LeaveByPersonDay
FROM LeaveDays
GROUP BY BranchIdentifier, TheDate, FullName;

IF OBJECT_ID('tempdb..#ClinicalHoursWorked') IS NOT NULL DROP TABLE #ClinicalHoursWorked;

SELECT
    l1.BranchIdentifier,
    l1.TheDate,
    l1.Theoretical_Available_Hours,
    ISNULL(SUM(lv.LeaveHoursCapped), 0)                                AS Total_Leave_Hours,
    l1.Theoretical_Available_Hours - ISNULL(SUM(lv.LeaveHoursCapped), 0)
                                                                        AS Clinical_Hours_Worked
INTO #ClinicalHoursWorked
FROM #Layer1_TheoreticalHours l1
LEFT JOIN #LeaveByPersonDay lv
    ON lv.BranchIdentifier = l1.BranchIdentifier
   AND lv.TheDate = l1.TheDate
GROUP BY l1.BranchIdentifier, l1.TheDate, l1.Theoretical_Available_Hours;

DROP TABLE #BranchWorkingDays;
DROP TABLE #Layer1_TheoreticalHours;
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

-- 1) Per branch per day.
SELECT
    abd.BranchIdentifier,
    abd.AppointmentDate,
    abd.Total_Attended_Duration_Hours,
    chw.Clinical_Hours_Worked,
    abd.Total_Attended_Duration_Hours / NULLIF(chw.Clinical_Hours_Worked, 0)
                                                                        AS Optometrist_Utilisation
FROM #AttendedByBranchDay abd
JOIN #ClinicalHoursWorked chw
    ON chw.BranchIdentifier = abd.BranchIdentifier
   AND chw.TheDate = abd.AppointmentDate
ORDER BY abd.BranchIdentifier, abd.AppointmentDate;

-- 2) Rolled up per branch (whole date range covered by the fact table).
SELECT
    abd.BranchIdentifier,
    SUM(abd.Total_Attended_Duration_Hours)                             AS Total_Attended_Duration_Hours,
    SUM(chw.Clinical_Hours_Worked)                                     AS Total_Clinical_Hours_Worked,
    SUM(abd.Total_Attended_Duration_Hours) / NULLIF(SUM(chw.Clinical_Hours_Worked), 0)
                                                                        AS Optometrist_Utilisation
FROM #AttendedByBranchDay abd
JOIN #ClinicalHoursWorked chw
    ON chw.BranchIdentifier = abd.BranchIdentifier
   AND chw.TheDate = abd.AppointmentDate
GROUP BY abd.BranchIdentifier
ORDER BY abd.BranchIdentifier;

DROP TABLE #OptometristAppointmentDetail;
DROP TABLE #ClinicalHoursWorked;
DROP TABLE #AttendedByBranchDay;
