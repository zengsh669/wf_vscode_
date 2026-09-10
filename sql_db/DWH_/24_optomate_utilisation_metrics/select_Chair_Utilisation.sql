/*
 Chair Utilisation — FACT TABLE (draft, not business-approved)
 Grain: one row per attended appointment. Numerator only (actual duration) —
 the denominator (theoretical capacity) is a branch-level constant, not tied
 to any appointment row, and is applied separately in the METRICS section.
 Attended = APP_PROGRESS IN (2,3,4,5,10) (same definition as Script-to-Sale).
 Full rules and evidence: DESIGN.md.
*/

IF OBJECT_ID('tempdb..#ChairAppointmentDetail') IS NOT NULL DROP TABLE #ChairAppointmentDetail;

SELECT
    a.ID                AS AppointmentID,
    a.BRANCH_IDENTIFIER AS BranchIdentifier,
    a.USER_IDENTIFIER   AS OptometristIdentifier,
    a.PATIENTID         AS PatientID,
    CAST(a.STARTDATE AS DATE) AS AppointmentDate,
    a.STARTDATE         AS StartDateTime,
    a.ENDDATE           AS EndDateTime,
    a.DURATION          AS DurationMinutes  -- verified reliable, matches DATEDIFF(MINUTE, STARTDATE, ENDDATE)
INTO #ChairAppointmentDetail
FROM APPOINTMENT a
WHERE a.APP_PROGRESS IN (2, 3, 4, 5, 10)  -- Attended (see DESIGN.md decode table)
  AND a.IS_BREAK = 0
  AND a.PATIENTID > 0;

-- Output the fact table.
SELECT *
FROM #ChairAppointmentDetail
ORDER BY AppointmentDate DESC, BranchIdentifier, AppointmentID;

-- ============================================================================
-- DENOMINATOR CONFIG — Total Available Chair Hours placeholder parameters,
-- one row per branch (not global — different branches may run different
-- appointment density / slot length). Replace with business-confirmed
-- values once available. See DESIGN.md for rationale.
-- ============================================================================
DECLARE @SlotConfig TABLE (BranchIdentifier VARCHAR(10), SlotsPerDay INT, MinutesPerSlot INT);
INSERT INTO @SlotConfig VALUES
    ('DUB', 13, 30),
    ('LIT', 13, 30),
    ('MAK', 13, 30),
    ('ORA', 13, 30),
    ('WOL', 13, 30);

-- ============================================================================
-- METRICS — Chair Utilisation = Total Attended Appointment Duration (hours)
-- ÷ Total Available Chair Hours, per branch.
-- Working Days = distinct dates with at least one attended appointment
-- (from the fact table itself — already excludes days with zero
-- appointments, e.g. public holidays).
-- ============================================================================
SELECT
    cad.BranchIdentifier,
    COUNT(DISTINCT cad.AppointmentDate)                        AS WorkingDays,
    sc.SlotsPerDay,
    sc.MinutesPerSlot,
    SUM(cad.DurationMinutes) / 60.0                             AS Total_Attended_Duration_Hours,
    COUNT(DISTINCT cad.AppointmentDate) * sc.SlotsPerDay * sc.MinutesPerSlot / 60.0
                                                                 AS Total_Available_Chair_Hours,
    (SUM(cad.DurationMinutes) / 60.0)
        / NULLIF(COUNT(DISTINCT cad.AppointmentDate) * sc.SlotsPerDay * sc.MinutesPerSlot / 60.0, 0)
                                                                 AS Chair_Utilisation
FROM #ChairAppointmentDetail cad
JOIN @SlotConfig sc ON sc.BranchIdentifier = cad.BranchIdentifier
GROUP BY cad.BranchIdentifier, sc.SlotsPerDay, sc.MinutesPerSlot
ORDER BY cad.BranchIdentifier;

DROP TABLE #ChairAppointmentDetail;
