-- DentistLeaveHours reconstruction — HrsPaid branch only (NOT YET ACCURATE)
-- Status: VALIDATED AS RUNNABLE, BUT KNOWN INACCURATE — checked against one employee's
-- actual worked hours; the query returned rows the employee confirmed they never worked.
-- Do NOT share with Monique yet. Kept here so the known issues are visible in one place
-- rather than only in conversation history.
--
-- Source: ConnX.dbo.Q2AIR_Shift_Transaction (shift/timesheet transactions), bridged to
-- q2employees via Q2AIR_Employee (emp_id <-> emp_code are two different numbering systems —
-- confirmed by testing, NOT a simple int/varchar cast).
--
-- KNOWN ISSUES (unresolved):
-- 1. Q2AIR_Shift_Transaction contains system-generated future shift placeholders — rows with
--    units = 0 AND income_type_id IS NULL are a clean, mutually exclusive category (verified:
--    across 5 years, exactly 2 categories exist — Hrs=0+TypeNull and Hrs>0+TypeHasValue, no
--    mixed cases). Sampling confirmed these are NOT deleted/reversed/cancelled records
--    (is_deleted='N', is_for_deletion='N', is_reversal='N', is_current='Y') but rather
--    pre-scheduled future rostered shifts not yet actualised.
--    Filter applied below: AND s.units > 0 — this removes the units=0 placeholder rows.
-- 2. Even after the units > 0 filter, a specific employee's record was checked and found to
--    contain ~100 rows of regular, evenly-spaced "Normal No Exp" / "BRK30 MIN Unpaid" shifts
--    (4 per working day) that the employee confirmed are NOT real — these look like a
--    standard rostered-shift template rather than actual worked/paid hours. This pattern was
--    NOT resolved by the units > 0 filter (these rows had units > 0).
--    HYPOTHESIS (unverified): Q2AIR_Shift_Transaction may be the ROSTERING system's table,
--    not the equivalent of Qlik's source table _ipvEmployeeTrans (an actual PAYROLL
--    transaction table, i.e. hours already processed/paid). If so, this may be a structural
--    mismatch, not fixable by adding more WHERE filters — needs business/IT input on whether
--    a different ConnX table represents processed pay transactions rather than rostered shifts.
-- 3. Cost Centre is NULL for ~93% of rows because s.cost_account_code_id itself is NULL for
--    that share of source rows (confirmed: 405,897 of 437,346 rows) — not a JOIN failure
--    (JOIN success rate is 100% whenever cost_account_code_id is populated). This appears to
--    be a genuine source data completeness gap.
-- 4. "Other Leave" in Qlik's HrsPaid wildmatch list has no single corresponding
--    Q2AIR_Income_Type value — it likely spans several specific income types (Compassionate,
--    Emergency Lve, Jury Leave, Study Leave, Fam Dom Vio Lve, Miscarriage/StB, Weather Events,
--    Well being Day). Not yet mapped to a definitive inclusion list.
-- 5. Whether Q2AIR_Shift_Transaction / Q2AIR_Income_Type text values actually line up with
--    Qlik's wildmatch'd Transaction Type names has not been directly verified.
--
-- Given issue #2, this branch should be treated as unreliable until resolved with Monique/IT,
-- even though it runs without error and issue #1's filter is applied.

SELECT
    CAST(s.emp_id AS VARCHAR(10)) + '|' + CONVERT(VARCHAR(10), p_period.pe_date, 112)   AS [Payroll_KEY],
    qe.emp_code                                                       AS [Employee ID],
    c.description                                                     AS [Cost Centre],
    s.units                                                           AS [Hrs],
    it.name                                                           AS [Transaction Type],
    NULL                                                              AS [Leave Reason],
    it.name                                                           AS [Leave Type Standardised],
    'HrsPaid'                                                         AS [SourceCalc],
    pos.Department                                                    AS [Default Cost Account Description],
    p_period.pe_date                                                  AS [Payroll Run Date],
    e.emp_code                                                        AS [Employee Code],
    e.surname + ', ' + e.given_name                                   AS [Full Name]
FROM ConnX.dbo.Q2AIR_Shift_Transaction s
LEFT JOIN ConnX.dbo.Q2AIR_Employee qe
    ON s.emp_id = qe.employee_id
LEFT JOIN ConnX.dbo.q2employees e
    ON qe.emp_code = e.emp_code
LEFT JOIN ConnX.dbo.Q2AIR_Income_Type it
    ON s.income_type_id = it.income_type_id
LEFT JOIN ConnX.dbo.q2cost_accounts c
    ON s.cost_account_code_id = c.cost_account_id
LEFT JOIN ConnX.dbo.q2period_end_dates p_period
    ON CAST(s.start_local_dt AS DATE) BETWEEN DATEADD(DAY, -6, p_period.pe_date) AND p_period.pe_date
LEFT JOIN ConnX.dbo.q2vHREmployee_Position pos
    ON e.emp_code = pos.emp_code
    AND p_period.pe_date BETWEEN pos.Date_Held_From AND ISNULL(pos.Date_Held_To, '9999-12-31')
WHERE s.start_local_dt >= DATEADD(YEAR, -5, GETDATE())
  AND s.units > 0
--   AND pos.Role_Name IN ('Dentist', 'Dentist Casual', 'Dentist Clinical Lead', 'Associate Clinical Dentist Lead')

ORDER BY [Full Name], [Payroll Run Date] DESC;
