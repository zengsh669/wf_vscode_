/*
 ConnX Optometrist / Work Pattern / Leave — exploration query (draft, not business-approved)
 Source: ConnX (HR/payroll system), NOT Optomate — separate database, referenced here as a
 candidate source for Optometrist Utilisation's denominator (Clinical Hours Worked), since
 CLOCKINOUT (Optomate) was found to have systemic data-quality issues (same-instant multi-branch
 clock records, even for confirmed real optometrists — see DESIGN.md).

 Grain: one row per optometrist per leave transaction; optometrists with no leave in the lookback
 window still appear once (LEFT JOIN), with leave columns NULL.

 [Position Held From] / [Position Held To] — the employment date range for this Role_Name/
 Department combination (Date_Held_To NULL = still current). Kept as columns (not filtered to
 "currently active" only) so a past optometrist's tenure can still be matched against Optomate
 attendance that falls within their employment window — filtering to Date_Held_To IS NULL would
 silently drop anyone no longer employed, even for dates while they were.

 Role_Name LIKE '%Optometrist%' matches both 'Optometrist' and 'Optometrist Lead' — not yet
 confirmed exhaustive against all Role_Name values in ConnX.
*/

WITH LatestWorkPattern AS (
    SELECT emp_code, pattern_id
    FROM (
        SELECT
            emp_code,
            pattern_id,
            ROW_NUMBER() OVER (
                PARTITION BY emp_code
                ORDER BY date_effective DESC
            ) AS rn
        FROM [ConnX].[dbo].[q2employee_work_patterns]
    ) x
    WHERE rn = 1
)
SELECT
    e.emp_code                         AS [Employee ID],
    e.surname + ', ' + e.given_name    AS [Full Name],
    pos.Role_Name,
    pos.Department                     AS [Cost Centre],
    pos.Date_Held_From                 AS [Position Held From],
    pos.Date_Held_To                   AS [Position Held To],
    wp.description                     AS [Work Pattern Description],
    h.date_start                       AS [Leave Date Start],
    h.hours                            AS [Leave Hours],
    h.type_desc                        AS [Leave Transaction Type],
    h.reason_desc                      AS [Leave Reason]
FROM [ConnX].[dbo].[q2employees] e
JOIN [ConnX].[dbo].[q2vHREmployee_Position] pos
    ON e.emp_code = pos.emp_code
LEFT JOIN LatestWorkPattern lwp
    ON e.emp_code = lwp.emp_code
LEFT JOIN [ConnX].[dbo].[q2work_patterns] wp
    ON lwp.pattern_id = wp.pattern_id
LEFT JOIN [ConnX].[dbo].[q2vEmployeeLeaveHistory] h
    ON e.emp_code = h.emp_code
    AND h.date_start >= DATEADD(YEAR, -1, GETDATE())
WHERE pos.Role_Name LIKE '%Optometrist%'
ORDER BY [Full Name], pos.Date_Held_From DESC, h.date_start DESC;

-- ============================================================================
-- SUMMARY — one row per optometrist per position held (Cost Centre, employment
-- date range, Work Pattern). No leave detail here — this is the roster/pattern
-- reference list to hand-convert Work Pattern Description into a daily-hours
-- number (manual step, decided 2026-09-11; not parsed by SQL).
-- Run this block on its own (it redeclares its own CTE — a WITH clause only
-- extends to the one statement right after it, so it can't reuse the CTE
-- from the block above).
-- ============================================================================
WITH LatestWorkPattern AS (
    SELECT emp_code, pattern_id
    FROM (
        SELECT
            emp_code,
            pattern_id,
            ROW_NUMBER() OVER (
                PARTITION BY emp_code
                ORDER BY date_effective DESC
            ) AS rn
        FROM [ConnX].[dbo].[q2employee_work_patterns]
    ) x
    WHERE rn = 1
)
SELECT
    e.emp_code                         AS [Employee ID],
    e.surname + ', ' + e.given_name    AS [Full Name],
    pos.Role_Name,
    pos.Department                     AS [Cost Centre],
    pos.Date_Held_From                 AS [Position Held From],
    pos.Date_Held_To                   AS [Position Held To],
    wp.description                     AS [Work Pattern Description]
FROM [ConnX].[dbo].[q2employees] e
JOIN [ConnX].[dbo].[q2vHREmployee_Position] pos
    ON e.emp_code = pos.emp_code
LEFT JOIN LatestWorkPattern lwp
    ON e.emp_code = lwp.emp_code
LEFT JOIN [ConnX].[dbo].[q2work_patterns] wp
    ON lwp.pattern_id = wp.pattern_id
WHERE pos.Role_Name LIKE '%Optometrist%'
ORDER BY [Full Name], pos.Date_Held_From DESC;
